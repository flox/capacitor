{
  devshell,
  data,
  pkgs,
  lib,
  floxpkgs,
  pins,
  ...
}: let
  calledFloxEnv = data.func data.attrs;
  finalPaths = [calledFloxEnv] ++ pins.versions.${pkgs.system};
in
  (devshell.legacyPackages.${pkgs.system}.mkNakedShell rec {
    name = "ops-env";
    profile = let
      needsPythonVSCodeHack = data.attrs.programs ? python &&
        builtins.elem "ms-python.python" (data.attrs.programs.vscode.extensions or []);
    in pkgs.buildEnv {
      name = "wrapper";
      paths = finalPaths ++ lib.optional needsPythonVSCodeHack pkgs.jq;

      postBuild = let
        versioned =
          builtins.filter (x: builtins.isString x && !builtins.hasContext x)
          calledFloxEnv.passthru.paths;
        split = map (x: builtins.concatStringsSep " " (lib.strings.splitString "@" x)) versioned;
        /*
         ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo $HOME/.config/flox/ )
         if compgen -G "$ROOT/.flox-${name}"* >/dev/null; then
           rm "$ROOT/.flox-${name}"*
         fi
         ${builtins.concatStringsSep "\n" (map (
             x: ''
               echo Searching: "${x}"
               ref=$( AS_FLAKEREF=1 ${floxpkgs.apps.${pkgs.system}.find-version.program} ${x})
               echo Installing: "$ref"
               flox profile install --profile "$ROOT/.flox-${name}" $ref
             ''
           )
           split)}
         flox profile wipe-history --profile "$ROOT/.flox-${name}" >/dev/null 2>/dev/null
         */
        envBash = pkgs.writeTextDir "env.bash" ''
          export PATH="@DEVSHELL_DIR@/bin:$PATH"
          ${data.attrs.hooks.postShellHook or ""}
          ${lib.optionalString needsPythonVSCodeHack ''
            SETTINGS=.vscode/settings.json
            PYTHON=$(which python)
            if [[ -f $SETTINGS ]]; then
                tmp=$(mktemp)
                cp $SETTINGS $tmp
                jq --arg PYTHON $PYTHON '."python.defaultInterpreterPath" |= $PYTHON' $tmp > $SETTINGS
                rm $tmp
            else
                mkdir -p .vscode
                jq -n --arg PYTHON $PYTHON '{"python.defaultInterpreterPath": $PYTHON}' > $SETTINGS
            fi

            cat <<EOF
            If you have previously selected a Python interpreter for VS Code in this workspace, you'll need to clear that setting:
            - open command palette (Mac: ⇧+⌘+P, Linux: Ctrl+Shift+P)
            - run "Python: Clear Workspace Interpreter Setting"
            EOF
            echo
          ''}

        '';
      in "substitute ${envBash}/env.bash $out/env.bash --subst-var-by DEVSHELL_DIR $out";
    };
  })
  // {
    passthru.paths =
      builtins.filter (x: !(builtins.isString x && !builtins.hasContext x))
      (calledFloxEnv.passthru.paths ++ pins.versions.${pkgs.system});
    passthru.pure-paths =
      let paths = builtins.filter (x: !(builtins.isString x && !builtins.hasContext x))
                  (calledFloxEnv.passthru.paths);
      in
      map  (drv:
        {
          storePaths = lib.attrValues (lib.genAttrs drv.outputs (output: builtins.unsafeDiscardStringContext drv.${output}.outPath));
        } // (if drv?attribute_path
        then {
          active = true;
          attrPath = builtins.concatStringsSep "." ([pkgs.system] ++ drv.attribute_path);
          originalUrl = null;
          url = null;
        }
        else {}
        ))
        paths;
    passthru.programs = calledFloxEnv.passthru.programs;
    passthru.data = data;
    passthru.pins = pins;
    passthru.python = calledFloxEnv.passthru.python;
  }
