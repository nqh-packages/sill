import * as Alchemy from "alchemy";
import * as Cloudflare from "@alchemy.run/cloudflare";
import * as Effect from "effect/Effect";

export default Alchemy.Stack(
  "SillLanding",
  { providers: Cloudflare.providers(), state: Cloudflare.state() },
  Effect.gen(function* () {
    const stage = yield* Alchemy.Stage;
    const isProd = stage === "prod";

    const site = yield* Cloudflare.Website.StaticSite("Site", {
      name: isProd ? "sill-uxheavy" : `sill-uxheavy-${stage}`,
      command: "pnpm build",
      outdir: "dist",
      workersDev: !isProd,
      domain: isProd ? "sill.uxheavy.com" : undefined,
      compatibility: { date: "2026-11-22" },
    });

    return { url: site.url, stage };
  }),
);
