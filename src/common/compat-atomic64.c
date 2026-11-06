/*
 * compat-atomic64.c — 64-битные __sync-примитивы для 32-битных архитектур,
 * где libgcc/libatomic их не предоставляет (MIPS32, ARMv7 и т.п.).
 *
 * GCC на mipsel генерирует вызовы __sync_fetch_and_add_8 и т.д. для
 * 64-битных счётчиков (статистика соединений), но libatomic экспортирует
 * только __atomic_*. Реализуем недостающие через __atomic_* — libatomic
 * их и предоставит.
 *
 * Функции нужны только когда компоновщик их требует; на x86_64/aarch64
 * они не вызываются (там операции инлайнятся).
 */

#include <stdint.h>

long long __sync_fetch_and_add_8 (volatile void *ptr, long long val);
long long __sync_add_and_fetch_8 (volatile void *ptr, long long val);
long long __sync_fetch_and_and_8 (volatile void *ptr, long long val);
long long __sync_fetch_and_or_8 (volatile void *ptr, long long val);

long long __sync_fetch_and_add_8 (volatile void *ptr, long long val) {
  return __atomic_fetch_add ((long long *) ptr, val, __ATOMIC_SEQ_CST);
}

long long __sync_add_and_fetch_8 (volatile void *ptr, long long val) {
  return __atomic_add_fetch ((long long *) ptr, val, __ATOMIC_SEQ_CST);
}

long long __sync_fetch_and_and_8 (volatile void *ptr, long long val) {
  return __atomic_fetch_and ((long long *) ptr, val, __ATOMIC_SEQ_CST);
}

long long __sync_fetch_and_or_8 (volatile void *ptr, long long val) {
  return __atomic_fetch_or ((long long *) ptr, val, __ATOMIC_SEQ_CST);
}
