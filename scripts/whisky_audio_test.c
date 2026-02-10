/*
 * whisky_audio_test.c
 *
 * This file is part of Whisky.
 *
 * Whisky is free software: you can redistribute it and/or modify it under the terms
 * of the GNU General Public License as published by the Free Software Foundation,
 * either version 3 of the License, or (at your option) any later version.
 *
 * Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with Whisky.
 * If not, see https://www.gnu.org/licenses/.
 *
 * Minimal Windows audio test helper for Whisky audio diagnostics.
 * Uses WinMM waveOut API for maximum Wine compatibility.
 *
 * Compile: x86_64-w64-mingw32-gcc -o WhiskyAudioTest.exe whisky_audio_test.c -lwinmm -lm
 *
 * Usage:
 *   WhiskyAudioTest.exe          - Silent test (initialize, write silence, exit)
 *   WhiskyAudioTest.exe --beep   - Play 440Hz test tone for 100ms
 *
 * Output: Single JSON line on stdout with test result.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <mmsystem.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main(int argc, char *argv[]) {
    int beep_mode = 0;
    if (argc > 1 && strcmp(argv[1], "--beep") == 0) {
        beep_mode = 1;
    }

    WAVEFORMATEX wfx;
    memset(&wfx, 0, sizeof(wfx));
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 2;
    wfx.nSamplesPerSec = 44100;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = wfx.nChannels * wfx.wBitsPerSample / 8;
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;
    wfx.cbSize = 0;

    HWAVEOUT hWaveOut = NULL;
    MMRESULT result = waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, 0, 0, CALLBACK_NULL);

    if (result != MMSYSERR_NOERROR) {
        printf("{\"status\":\"error\",\"api\":\"waveOut\",\"code\":%d}\n", (int)result);
        fflush(stdout);
        return 1;
    }

    /* Generate 100ms audio buffer */
    int num_samples = 44100 / 10;
    int buf_size = num_samples * wfx.nBlockAlign;
    char *buf = (char *)calloc(1, buf_size);

    if (!buf) {
        printf("{\"status\":\"error\",\"api\":\"waveOut\",\"code\":-1}\n");
        fflush(stdout);
        waveOutClose(hWaveOut);
        return 1;
    }

    if (beep_mode) {
        /* Generate 440Hz sine wave (A4) */
        short *samples = (short *)buf;
        int i;
        for (i = 0; i < num_samples; i++) {
            double t = (double)i / 44100.0;
            short val = (short)(32767.0 * sin(2.0 * M_PI * 440.0 * t));
            samples[i * 2] = val;       /* left channel */
            samples[i * 2 + 1] = val;   /* right channel */
        }
    }
    /* else: buffer is already zeroed (silence) */

    WAVEHDR header;
    memset(&header, 0, sizeof(header));
    header.lpData = buf;
    header.dwBufferLength = buf_size;

    result = waveOutPrepareHeader(hWaveOut, &header, sizeof(header));
    if (result != MMSYSERR_NOERROR) {
        printf("{\"status\":\"error\",\"api\":\"waveOutPrepareHeader\",\"code\":%d}\n",
               (int)result);
        fflush(stdout);
        waveOutClose(hWaveOut);
        free(buf);
        return 1;
    }

    result = waveOutWrite(hWaveOut, &header, sizeof(header));
    if (result != MMSYSERR_NOERROR) {
        printf("{\"status\":\"error\",\"api\":\"waveOutWrite\",\"code\":%d}\n", (int)result);
        fflush(stdout);
        waveOutUnprepareHeader(hWaveOut, &header, sizeof(header));
        waveOutClose(hWaveOut);
        free(buf);
        return 1;
    }

    /* Wait for playback to complete */
    while (!(header.dwFlags & WHDR_DONE)) {
        Sleep(10);
    }

    waveOutUnprepareHeader(hWaveOut, &header, sizeof(header));
    waveOutClose(hWaveOut);
    free(buf);

    printf("{\"status\":\"ok\",\"api\":\"waveOut\",\"sampleRate\":44100,"
           "\"channels\":2,\"beep\":%s}\n",
           beep_mode ? "true" : "false");
    fflush(stdout);
    return 0;
}
