/*
 *  bridge.c
 *  WhiskyDiscordBridge
 *
 *  This file is part of Whisky.
 *
 *  Whisky is free software: you can redistribute it and/or modify it under the terms
 *  of the GNU General Public License as published by the Free Software Foundation,
 *  either version 3 of the License, or (at your option) any later version.
 *
 *  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 *  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with Whisky.
 *  If not, see https://www.gnu.org/licenses/.
 *
 *  Relays the Discord RPC named pipe inside a bottle to the Discord client
 *  running on the host. Both ends speak the same framing (a little-endian
 *  opcode and length, then JSON), so this never parses a message: it is a byte
 *  pump with a pipe on one side and a unix socket on the other.
 */

#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PIPE_NAME "\\\\.\\pipe\\discord-ipc-0"
#define INSTANCE_MUTEX "Local\\WhiskyDiscordBridge"
#define BUFFER_SIZE 4096
/* Discord's client libraries walk discord-ipc-0 through discord-ipc-9. */
#define SOCKET_CANDIDATES 10
/* Acceptors, each holding one pipe instance open and waiting. A single acceptor
 * leaves a window between a client connecting and the next instance being
 * posted, which two clients starting together land in: the second gets
 * ERROR_PIPE_BUSY. Discord's own libraries retry that, but nothing here should
 * depend on the client being polite. */
#define PENDING_INSTANCES 4
#define DEFAULT_GRACE_MS 10000

/* SYS_* from <sys/syscall.h>, offset into the BSD class by the stub below. */
#define SYS_READ 3
#define SYS_WRITE 4
#define SYS_CLOSE 6
#define SYS_SOCKET 97
#define SYS_CONNECT 98
#define SYS_SHUTDOWN 134

#define BSD_AF_UNIX 1
#define BSD_SOCK_STREAM 1
#define BSD_SHUT_RDWR 2

/* Wine's private process info class; see include/winternl.h in the Wine tree. */
#define ProcessWineMakeProcessSystem 1000

/* xnu's sockaddr_un: a length byte and a family byte, not the 16-bit family
 * Linux uses. Getting this wrong lands AF_UNSPEC in sun_family. */
struct bsd_sockaddr_un {
    unsigned char sun_len;
    unsigned char sun_family;
    char sun_path[104];
};

typedef LONG(WINAPI *nt_set_information_process)(HANDLE, ULONG, PVOID, ULONG);

struct connection {
    HANDLE pipe;
    int socket;
    volatile LONG references;
};

/* Sized so the finished path always fits sun_path. A directory longer than
 * this could not be reached through an AF_UNIX address at all. */
#define SOCKET_DIRECTORY_MAX (sizeof(((struct bsd_sockaddr_un *)0)->sun_path) - sizeof("discord-ipc-9"))

static char socket_directory[SOCKET_DIRECTORY_MAX];

static void log_line(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    fprintf(stderr, "whisky-discord-bridge: ");
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    fflush(stderr);
    va_end(args);
}

/*
 * PE code shares its address space with the unix side of Wine, so a `syscall`
 * instruction reaches xnu directly. Nothing else here can reach it: a PE module
 * cannot link libSystem, and the supported alternative, a PE plus a unixlib
 * half, would have to be built against the runtime's Wine instead of plain
 * MinGW, which would tie this binary to a Wine version.
 *
 * The stub is SysV because that is what xnu expects, while the compiler emits
 * MS-ABI calls; the attribute makes it lay the arguments out accordingly. Three
 * arguments is the most any call below needs, which keeps the shuffle clear of
 * r10 and its rcx clobber.
 */
__attribute__((sysv_abi)) LONG_PTR unix_syscall(LONG_PTR number, LONG_PTR first, LONG_PTR second, LONG_PTR third);
__asm__(".text\n\t"
        ".globl unix_syscall\n"
        "unix_syscall:\n\t"
        "movq %rdi, %rax\n\t"
        "addq $0x2000000, %rax\n\t"
        "movq %rsi, %rdi\n\t"
        "movq %rdx, %rsi\n\t"
        "movq %rcx, %rdx\n\t"
        "syscall\n\t"
        "jnc 1f\n\t"
        "negq %rax\n"
        "1:\n\t"
        "ret\n");

static int unix_socket(void)
{
    return (int)unix_syscall(SYS_SOCKET, BSD_AF_UNIX, BSD_SOCK_STREAM, 0);
}

static int unix_connect(int fd, const struct bsd_sockaddr_un *address)
{
    return (int)unix_syscall(SYS_CONNECT, fd, (LONG_PTR)address, sizeof(*address));
}

static LONG_PTR unix_read(int fd, void *buffer, DWORD length)
{
    return unix_syscall(SYS_READ, fd, (LONG_PTR)buffer, length);
}

static LONG_PTR unix_write(int fd, const void *buffer, DWORD length)
{
    return unix_syscall(SYS_WRITE, fd, (LONG_PTR)buffer, length);
}

static void unix_close(int fd)
{
    unix_syscall(SYS_CLOSE, fd, 0, 0);
}

static void unix_shutdown(int fd)
{
    unix_syscall(SYS_SHUTDOWN, fd, BSD_SHUT_RDWR, 0);
}

/* Whisky passes --dir because a PE process sees Wine's Windows environment,
 * where the host's TMPDIR may not have survived. The fallbacks are for running
 * this by hand. */
static BOOL resolve_socket_directory(const char *requested)
{
    const char *directory = requested;
    size_t length;

    if (!directory || !*directory) directory = getenv("TMPDIR");
    if (!directory || !*directory) directory = getenv("XDG_RUNTIME_DIR");
    if (!directory || !*directory) directory = "/tmp";

    length = strlen(directory);
    if (length > sizeof(socket_directory) - 2) {
        log_line("socket directory does not fit a unix address: %s", directory);
        return FALSE;
    }

    memcpy(socket_directory, directory, length);
    if (length && socket_directory[length - 1] != '/') socket_directory[length++] = '/';
    socket_directory[length] = 0;
    return TRUE;
}

static int connect_to_discord(void)
{
    int index;

    for (index = 0; index < SOCKET_CANDIDATES; index++) {
        struct bsd_sockaddr_un address;
        int fd = unix_socket();

        if (fd < 0) {
            log_line("socket() failed: %d", -fd);
            return -1;
        }

        memset(&address, 0, sizeof(address));
        address.sun_len = sizeof(address);
        address.sun_family = BSD_AF_UNIX;
        snprintf(address.sun_path, sizeof(address.sun_path), "%sdiscord-ipc-%d", socket_directory, index);

        if (unix_connect(fd, &address) == 0) {
            log_line("relaying to %s", address.sun_path);
            return fd;
        }

        unix_close(fd);
    }

    return -1;
}

static void connection_release(struct connection *connection)
{
    if (InterlockedDecrement(&connection->references) != 0) return;
    CloseHandle(connection->pipe);
    unix_close(connection->socket);
    free(connection);
}

static DWORD WINAPI pump_pipe_to_socket(void *parameter)
{
    struct connection *connection = parameter;
    char buffer[BUFFER_SIZE];
    DWORD received;

    while (ReadFile(connection->pipe, buffer, sizeof(buffer), &received, NULL) && received) {
        DWORD sent = 0;

        while (sent < received) {
            LONG_PTR written = unix_write(connection->socket, buffer + sent, received - sent);
            if (written <= 0) goto finished;
            sent += (DWORD)written;
        }
    }

finished:
    /* The other pump is parked in read() on this socket; shutting it down is
     * what wakes it. */
    unix_shutdown(connection->socket);
    connection_release(connection);
    return 0;
}

static void pump_socket_to_pipe(struct connection *connection)
{
    char buffer[BUFFER_SIZE];
    LONG_PTR received;

    while ((received = unix_read(connection->socket, buffer, sizeof(buffer))) > 0) {
        DWORD sent = 0;

        while (sent < (DWORD)received) {
            DWORD written = 0;
            if (!WriteFile(connection->pipe, buffer + sent, (DWORD)received - sent, &written, NULL) || !written) {
                return;
            }
            sent += written;
        }
    }
}

static DWORD WINAPI service_client(void *parameter)
{
    HANDLE pipe = parameter;
    struct connection *connection;
    HANDLE pump;
    int fd;

    fd = connect_to_discord();
    if (fd < 0) {
        /* Discord is not running. Drop the client rather than hold a pipe that
         * goes nowhere: its library then walks on to the next index and reports
         * "no Discord" the way it would on Windows. */
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        return 0;
    }

    connection = calloc(1, sizeof(*connection));
    if (!connection) {
        unix_close(fd);
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        return 0;
    }

    connection->pipe = pipe;
    connection->socket = fd;
    connection->references = 2;

    pump = CreateThread(NULL, 0, pump_pipe_to_socket, connection, 0, NULL);
    if (!pump) {
        connection->references = 1;
        connection_release(connection);
        return 0;
    }
    CloseHandle(pump);

    pump_socket_to_pipe(connection);

    /* The other pump is parked in ReadFile; disconnecting fails that read. */
    DisconnectNamedPipe(connection->pipe);
    connection_release(connection);
    return 0;
}

static DWORD WINAPI accept_clients(void *parameter)
{
    (void)parameter;

    for (;;) {
        HANDLE client;
        HANDLE worker;
        HANDLE pipe = CreateNamedPipeA(PIPE_NAME, PIPE_ACCESS_DUPLEX,
                                       PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                                       PIPE_UNLIMITED_INSTANCES, BUFFER_SIZE, BUFFER_SIZE, 0, NULL);

        if (pipe == INVALID_HANDLE_VALUE) {
            log_line("CreateNamedPipe failed: %lu", GetLastError());
            Sleep(1000);
            continue;
        }

        if (!ConnectNamedPipe(pipe, NULL) && GetLastError() != ERROR_PIPE_CONNECTED) {
            CloseHandle(pipe);
            continue;
        }

        /* Hand the client off so the loop can post the next pipe instance
         * immediately: a gap here is a window where the name does not exist and
         * a connecting game sees nothing. */
        client = pipe;
        worker = CreateThread(NULL, 0, service_client, client, 0, NULL);
        if (!worker) {
            DisconnectNamedPipe(client);
            CloseHandle(client);
            continue;
        }
        CloseHandle(worker);
    }

    return 0;
}

/*
 * Become a Wine "system" process and return the event wineserver signals when
 * it shuts down. System processes are not counted as reasons to keep the prefix
 * alive, so the bridge stops holding a bottle open once the game exits, and
 * exits with the prefix rather than outliving it.
 */
static HANDLE make_process_system(void)
{
    HANDLE event = NULL;
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    nt_set_information_process set_information;

    if (!ntdll) return NULL;

    set_information = (nt_set_information_process)(void *)GetProcAddress(ntdll, "NtSetInformationProcess");
    if (!set_information) return NULL;

    if (set_information(GetCurrentProcess(), ProcessWineMakeProcessSystem, &event, sizeof(HANDLE *)) != 0) {
        return NULL;
    }

    return event;
}

int main(int argc, char **argv)
{
    const char *requested_directory = NULL;
    DWORD grace = DEFAULT_GRACE_MS;
    HANDLE shutdown_event;
    HANDLE mutex;
    int index;

    for (index = 1; index < argc; index++) {
        if (!strcmp(argv[index], "--dir") && index + 1 < argc) {
            requested_directory = argv[++index];
        } else if (!strcmp(argv[index], "--grace") && index + 1 < argc) {
            grace = (DWORD)strtoul(argv[++index], NULL, 10);
        }
    }

    /* One bridge per prefix. A second launch (a game started while another is
     * already running) would find the pipe name taken anyway. */
    mutex = CreateMutexA(NULL, TRUE, INSTANCE_MUTEX);
    if (!mutex || GetLastError() == ERROR_ALREADY_EXISTS) return 0;

    if (!resolve_socket_directory(requested_directory)) return 1;
    log_line("serving %s from %s", PIPE_NAME, socket_directory);

    for (index = 0; index < PENDING_INSTANCES; index++) {
        if (!CreateThread(NULL, 0, accept_clients, NULL, 0, NULL)) {
            log_line("could not start an accept loop: %lu", GetLastError());
            return 1;
        }
    }

    /* Stay an ordinary process for the grace window. Whisky starts the bridge
     * just before the game, and a prefix with no user process in it starts
     * shutting down; counting until the game arrives keeps a cold prefix from
     * tearing itself down between the two launches. */
    Sleep(grace);

    shutdown_event = make_process_system();
    if (!shutdown_event) {
        /* Not Wine, or a Wine without the call. Keep relaying; the cost is that
         * this process alone can hold the prefix open. */
        log_line("could not become a system process; the bottle will stay busy");
        Sleep(INFINITE);
        return 0;
    }

    WaitForSingleObject(shutdown_event, INFINITE);
    return 0;
}
