#!/usr/bin/env bun
/**
 * Release script for Cafein.
 *
 * One interactive command that: picks the next version from your conventional
 * commits, generates release notes, bumps the project version, builds + signs +
 * notarizes a DMG, tags the commit, and publishes a GitHub Release with the DMG
 * attached.
 *
 * Everything runs locally — the only external services are Apple notarization
 * and GitHub Releases, both free. No GitHub Actions minutes are used.
 *
 * Usage:
 *   bun release                 — cut a release; GitHub Actions signs + attaches the DMG
 *   bun release --yes           — no prompts: accept the suggested version and ship
 *   bun release --dry-run       — show the plan, change nothing
 *   bun release --local-dmg     — also build + notarize the DMG locally (needs your cert)
 *
 * The default path needs no Apple credentials locally — the release.yml workflow
 * signs and notarizes from repo Secrets. --local-dmg builds on your Mac instead
 * (see tools/release.sh header); pass TEAM_ID=... or you'll be prompted.
 */
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

import * as p from "@clack/prompts";
import { ConventionalChangelog } from "conventional-changelog";

const ROOT = `${import.meta.dir}/..`;
const PBXPROJ = `${ROOT}/cafein.xcodeproj/project.pbxproj`;
const DMG_PATH = `${ROOT}/build/Cafein.dmg`;

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const LOCAL_DMG = args.includes("--local-dmg");
const YES = args.includes("--yes") || args.includes("-y");

type BumpLevel = "patch" | "minor" | "major";

// ---------------------------------------------------------------------------
// Process helpers
// ---------------------------------------------------------------------------

/** Run a command, capture stdout. Rejects on non-zero exit. */
function run(cmd: string, cmdArgs: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, cmdArgs, { cwd: ROOT });
    let out = "";
    let err = "";

    proc.stdout.on("data", (d) => (out += d));
    proc.stderr.on("data", (d) => (err += d));
    proc.on("close", (code) =>
      code === 0
        ? resolve(out.trim())
        : reject(new Error(`${cmd} ${cmdArgs.join(" ")} failed:\n${err}`)),
    );
    proc.on("error", reject);
  });
}

/** Like run() but returns null instead of throwing (for best-effort queries). */
async function runOrNull(cmd: string, cmdArgs: string[]): Promise<string | null> {
  try {
    return (await run(cmd, cmdArgs)) || null;
  } catch {
    return null;
  }
}

/** Run a command inheriting stdio so the user sees live output (builds, etc.). */
function runInherit(
  cmd: string,
  cmdArgs: string[],
  env?: Record<string, string>,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, cmdArgs, {
      cwd: ROOT,
      stdio: "inherit",
      env: env ? { ...process.env, ...env } : process.env,
    });

    proc.on("close", (code) =>
      code === 0 ? resolve() : reject(new Error(`${cmd} exited ${code}`)),
    );
    proc.on("error", reject);
  });
}

/** A hardcoded shell pipeline (no user input) — used for the git tag query. */
function shell(cmd: string): Promise<string> {
  return new Promise((resolve) => {
    const proc = spawn("sh", ["-c", cmd], { cwd: ROOT });
    let out = "";

    proc.stdout.on("data", (d) => (out += d));
    proc.on("close", () => resolve(out.trim()));
    proc.on("error", () => resolve(""));
  });
}

// ---------------------------------------------------------------------------
// Version helpers
// ---------------------------------------------------------------------------

function normalize(version: string): string {
  const parts = version.split(".").map((n) => parseInt(n, 10) || 0);

  while (parts.length < 3) parts.push(0);

  return parts.slice(0, 3).join(".");
}

function bumpVersion(version: string, bump: BumpLevel): string {
  const [major, minor, patch] = normalize(version).split(".").map(Number);

  switch (bump) {
    case "major":
      return `${major + 1}.0.0`;
    case "minor":
      return `${major}.${minor + 1}.0`;
    case "patch":
      return `${major}.${minor}.${patch + 1}`;
  }
}

function detectBump(messages: string[]): BumpLevel {
  for (const msg of messages) {
    if (msg.includes("BREAKING CHANGE") || /^[a-z]+(\(.+\))?!:/.test(msg)) {
      return "major";
    }
  }
  for (const msg of messages) {
    if (/^feat(\(.+\))?:/.test(msg)) {
      return "minor";
    }
  }

  return "patch";
}

/** Newest `vX.Y.Z` release tag (excludes pre-release suffixes), or null. */
async function getLatestTag(): Promise<{ tag: string; version: string } | null> {
  const out = await shell(
    "git tag -l 'v*' --sort=-v:refname | grep -vE '\\-(rc|beta|alpha)\\.' | head -1",
  );

  if (!out) return null;

  return { tag: out, version: out.replace(/^v/, "") };
}

async function getCommitsSince(
  tag: string | null,
): Promise<{ lines: string[]; messages: string[] }> {
  const range = tag ? `${tag}..HEAD` : "HEAD";
  const out = await runOrNull("git", [
    "log",
    range,
    "--format=%h %s",
    "--no-merges",
  ]);

  if (!out) return { lines: [], messages: [] };

  const lines = out.split("\n").filter(Boolean);
  const messages = lines.map((l) => l.slice(l.indexOf(" ") + 1));

  return { lines, messages };
}

/** Release notes (markdown) from conventional commits since `fromTag`. */
async function generateChangelog(fromTag: string | null): Promise<string> {
  const generator = new ConventionalChangelog()
    .loadPreset("conventionalcommits")
    .readRepository()
    .commits({ from: fromTag ?? "", merges: false })
    .options({ releaseCount: 1 });

  let notes = "";

  for await (const chunk of generator.write()) notes += chunk;

  // Drop the auto-generated version header — the tag name is the release title.
  return notes.replace(/^##?\s+.*?\n\n/, "").trim();
}

/** Current build number (max CURRENT_PROJECT_VERSION across configs). */
function currentBuild(proj: string): number {
  const builds = [...proj.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)].map((m) =>
    parseInt(m[1], 10),
  );

  return builds.length ? Math.max(...builds) : 0;
}

/** Current marketing version (first MARKETING_VERSION in the project). */
function currentMarketing(proj: string): string | null {
  return proj.match(/MARKETING_VERSION = ([0-9.]+);/)?.[1] ?? null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  p.intro(DRY_RUN ? "Cafein release (dry run)" : "Cafein release");

  if (!YES) {
    p.note(
      "1. Pick a version (based on your commits)\n2. Write the release notes\n3. Tag and publish the GitHub Release\n\nGitHub then builds, signs & notarizes the app for you — nothing else to do.",
      "What this does",
    );
  }

  const hasRemote = Boolean(await runOrNull("git", ["remote"]));

  // Clean tree required for a real run so the release commit is only the bump.
  if (!DRY_RUN) {
    const dirty = await runOrNull("git", ["status", "--porcelain"]);

    if (dirty) {
      p.cancel("Working tree has uncommitted changes. Commit them first.");
      process.exit(1);
    }
  }

  if (hasRemote) await runOrNull("git", ["fetch", "--tags"]);

  // --- Resolve current version + commits ---
  const proj = readFileSync(PBXPROJ, "utf8");
  const latest = await getLatestTag();
  const baseVersion = latest?.version ?? currentMarketing(proj) ?? "0.0.0";
  const { lines: commits, messages } = await getCommitsSince(latest?.tag ?? null);

  if (commits.length === 0 && !DRY_RUN && !YES) {
    const proceed = await p.confirm({
      message: `No commits since ${latest?.tag ?? "the beginning"}. Release anyway?`,
      initialValue: false,
    });

    if (p.isCancel(proceed) || !proceed) {
      p.outro("Nothing to release.");
      process.exit(0);
    }
  }

  p.note(
    commits.length ? commits.map((c) => `  ${c}`).join("\n") : "  (none)",
    `${commits.length} commit${commits.length === 1 ? "" : "s"} since ${latest?.tag ?? "the beginning"}`,
  );

  // --- Pick version ---
  const detected = detectBump(messages);
  const baseNorm = normalize(baseVersion);
  type Choice = BumpLevel | "current";
  const hints: Record<Choice, string> = {
    current: "ship this version as-is",
    patch: "bug fixes only",
    minor: "new features, nothing broken",
    major: "breaking changes",
  };
  const bumpOptions: { value: Choice; label: string; hint?: string }[] = [];

  // First release: offer shipping the current version as-is (no bump).
  if (!latest) {
    bumpOptions.push({ value: "current", label: `v${baseNorm}`, hint: hints.current });
  }

  bumpOptions.push(
    ...(["patch", "minor", "major"] as BumpLevel[]).map((level) => ({
      value: level as Choice,
      label: `${level} → v${bumpVersion(baseVersion, level)}${detected === level ? "  ← suggested" : ""}`,
      hint: hints[level],
    })),
  );

  const firstChoice: Choice = latest ? detected : "current";
  let selected: Choice = firstChoice;

  if (!YES) {
    const picked = await p.select({
      message: `What kind of release is this? (current v${baseNorm})`,
      options: bumpOptions,
      initialValue: firstChoice,
    });

    if (p.isCancel(picked)) {
      p.cancel("Cancelled.");
      process.exit(0);
    }

    selected = picked;
  }

  const nextVersion =
    selected === "current" ? baseNorm : bumpVersion(baseVersion, selected);
  const nextBuild = currentBuild(proj) + (selected === "current" ? 0 : 1);
  const tag = `v${nextVersion}`;

  // --- Notes ---
  const notes = (await generateChangelog(latest?.tag ?? null)) || "No notable changes.";

  p.note(`${tag}  (build ${nextBuild})\n\n${notes}`, "Release preview");

  if (DRY_RUN) {
    p.outro(
      `Dry run — would: bump → ${nextVersion}, tag ${tag}, ${hasRemote ? "push + create GitHub Release" : "(no git remote — local only)"}, then ${LOCAL_DMG ? "build + notarize the DMG locally" : "let GitHub Actions sign + attach the DMG"}.`,
    );
    return;
  }

  if (!YES) {
    const confirmed = await p.confirm({
      message: `Publish ${tag}? Tags the commit, pushes main, and creates the GitHub Release (GitHub then builds the app).`,
    });

    if (p.isCancel(confirmed) || !confirmed) {
      p.outro("Cancelled.");
      process.exit(0);
    }
  }

  // --- Bump version in the project ---
  const bumped = proj
    .replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${nextVersion};`)
    .replace(/CURRENT_PROJECT_VERSION = [^;]+;/g, `CURRENT_PROJECT_VERSION = ${nextBuild};`);

  writeFileSync(PBXPROJ, bumped);
  p.log.success(`Bumped to ${nextVersion} (build ${nextBuild}).`);

  // --- Optionally build the DMG locally (default: GitHub Actions signs it) ---
  if (LOCAL_DMG) {
    let teamId = process.env.TEAM_ID;

    if (!teamId) {
      const entered = await p.text({
        message: "Apple Team ID (10 chars):",
        validate: (v) =>
          v && /^[A-Z0-9]{10}$/.test(v) ? undefined : "Expected a 10-character Team ID",
      });

      if (p.isCancel(entered)) {
        p.cancel("Cancelled — version bump left in working tree (revert with git checkout).");
        process.exit(1);
      }

      teamId = entered;
    }

    const s = p.spinner();

    s.start("Building, signing & notarizing DMG (a few minutes)…");
    try {
      await runInherit("bash", ["tools/release.sh"], { TEAM_ID: teamId });
      s.stop("DMG built and notarized.");
    } catch (e) {
      s.stop("Build failed.");
      p.cancel(`${(e as Error).message}\nVersion bump left in working tree (git checkout to revert).`);
      process.exit(1);
    }
  }

  // --- Commit, tag, push ---
  await run("git", ["add", "cafein.xcodeproj/project.pbxproj"]);
  await run("git", ["commit", "-m", `chore(release): ${tag}`]);
  await run("git", ["tag", "-m", tag, tag]);
  p.log.success(`Committed and tagged ${tag}.`);

  if (!hasRemote) {
    p.outro(
      `Tagged ${tag} locally. No git remote configured, so nothing was pushed.\nAdd a remote, then: git push origin HEAD --tags`,
    );
    return;
  }

  await run("git", ["push", "origin", "HEAD"]);
  await run("git", ["push", "origin", tag]);
  p.log.success("Pushed commit and tag.");

  // --- GitHub Release ---
  const ghArgs = [
    "release",
    "create",
    tag,
    "--title",
    tag,
    "--notes",
    notes,
  ];

  if (LOCAL_DMG && existsSync(DMG_PATH)) ghArgs.push(DMG_PATH);

  const created = await runOrNull("gh", ghArgs);

  if (created === null) {
    p.outro(
      `Tag pushed, but \`gh release create\` failed (is gh authenticated?).\nRun manually:\n  gh ${ghArgs.map((a) => (a.includes(" ") ? `'${a}'` : a)).join(" ")}`,
    );
    return;
  }

  p.outro(
    `Shipped ${tag} 🚀\n${created}\n${LOCAL_DMG ? "DMG attached." : "GitHub Actions is signing + attaching the DMG now."}`,
  );
}

main().catch((e) => {
  p.cancel((e as Error).message);
  process.exit(1);
});
