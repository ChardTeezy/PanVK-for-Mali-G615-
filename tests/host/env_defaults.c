/* Host test for panvk_apply_env_defaults() (patches/0001). run-host-tests.sh extracts the
 * function from the patched panvk_instance.c into fn.inc, so this tests the shipped code. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "util/os_misc.h"
#include "util/simple_mtx.h"
#include "util/log.h"

void panvk_apply_env_defaults(const char *list, const char *origin);
#include "fn.inc"

static int
check(const char *k, const char *want)
{
   const char *v = getenv(k);
   int ok = want ? (v && !strcmp(v, want)) : !v;
   printf("%-4s %s=%s (want %s)\n", ok ? "ok" : "FAIL", k, v ? v : "(unset)",
          want ? want : "(unset)");
   return !ok;
}

int
main(void)
{
   setenv("PANVK_KEEP", "user", 1);
   panvk_apply_env_defaults(" PANVK_HEAP_MAX_MB=2048; PANVK_KEEP=profile;MESA_X=a=b;"
                            "HOME2=x;PANVK_DEBUG=sync;=v;novalue;PANVK_EMPTY=", "test");
   int f = 0;
   f += check("PANVK_HEAP_MAX_MB", "2048"); /* applied */
   f += check("PANVK_KEEP", "user");        /* user value wins */
   f += check("MESA_X", "a=b");             /* value may contain '=' */
   f += check("HOME2", NULL);               /* not a PANVK_/MESA_ key */
   f += check("PANVK_DEBUG", NULL);         /* rejected: parsed before the instance */
   f += check("PANVK_EMPTY", "");
   panvk_apply_env_defaults(NULL, "null");
   panvk_apply_env_defaults("", "empty");
   return f;
}
