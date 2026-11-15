/* Host test: which pan_env_defaults value Mesa's static driconf (the Android path) picks
 * for an application name. Args: triples of <applicationName> <engineName> <expected>. */
#include <stdio.h>
#include <string.h>
#include "util/xmlconfig.h"
#include "panvk_drirc.h"
int main(int argc, char **argv)
{
   int fails = 0;
   for (int i = 1; i + 2 < argc + 1; i += 3) {
      struct panvk_drirc d;
      memset(&d, 0, sizeof(d));
      panvk_parse_dri_options(&d, &(driConfigFileParseParams){
         .driverName = "panvk", .applicationName = argv[i], .engineName = argv[i + 1]});
      const char *got = d.misc.env_defaults ? d.misc.env_defaults : "(null)";
      int ok = !strcmp(got, argv[i + 2]);
      fails += !ok;
      printf("%-4s app=%-32s engine=%-6s env_defaults=\"%s\" vps_atomics=%d\n", ok ? "ok" : "FAIL",
             argv[i], argv[i + 1], got, d.misc.enable_vertex_pipeline_stores_atomics);
   }
   return fails != 0;
}
