#!/usr/bin/env nix-shell
# When using as a callable script, passing `--argstr path some/path` overrides $PWD.
#!nix-shell -p nix -i "nix-env -qaP --no-name --out-path --arg checkMeta true --argstr path $PWD -f"
{ checkMeta ? false
, path ? ./.
, supportedSystems
}:
let
  lib = import <nixpkgs/lib>;
  hydraJobs = import <nixpkgs/pkgs/top-level/release.nix>
    # Compromise: accuracy vs. resources needed for evaluation.
    {
      inherit supportedSystems;

      nixpkgsArgs = {
        config = {
          allowBroken = false;
          allowUnfree = true;
          allowInsecurePredicate = x: true;
          checkMeta = checkMeta;

          handleEvalIssue = reason: errormsg:
            let
              fatalErrors = [
                "unknown-meta" "broken-outputs"
              ];
            in if builtins.elem reason fatalErrors
              then abort errormsg
              else true;

          inHydra = true;
        };
      };
    };
  recurseIntoAttrs = attrs: attrs // { recurseForDerivations = true; };

  # hydraJobs leaves recurseForDerivations as empty attrmaps;
  # that would break nix-env and we also need to recurse everywhere.
  tweak = lib.mapAttrs
    (name: val:
      if name == "recurseForDerivations" then true
      else if lib.isAttrs val && val.type or null != "derivation"
              then recurseIntoAttrs (tweak val)
      else val
    );

  # Some of these contain explicit references to platform(s) we want to avoid;
  # some even (transitively) depend on ~/.nixpkgs/config.nix (!)
  blacklist = [
    "tarball" "metrics" "manual"
    "darwin-tested" "unstable" "stdenvBootstrapTools"
    "moduleSystem" "lib-tests" # these just confuse the output
  ];

in
  tweak (builtins.removeAttrs hydraJobs blacklist)
