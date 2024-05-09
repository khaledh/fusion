#pragma once

#include <stddef.h>

typedef struct {} FILE;

extern FILE* stdout;
extern FILE* stderr;

size_t fwrite(const void* buffer, size_t size, size_t count, FILE* stream);
int fflush(FILE *stream);
