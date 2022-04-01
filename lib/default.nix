{
  self,
  args,
}: {
  # UNSAFE: Get latest version from non-empty list of drvs
  # primary :: [drv] -> drv
  primary = values:
    with builtins;
      head (
        sort (a: b:
          isAttrs a
          && isAttrs b
          && a ? version
          && builtins.isString a.version
          && b ? version
          && builtins.isString b.version
          && compareVersions a.version b.version >= 0)
        values
      );

  # Make the versions attribute safe
  # sanitizeVersionName :: String -> String
  sanitizeVersionName = with builtins;
  with args.nixpkgs.lib.strings;
    string:
      args.nixpkgs.lib.pipe string [
        unsafeDiscardStringContext
        # Strip all leading "."
        (x: elemAt (match "\\.*(.*)" x) 0)
        (split "[^[:alnum:]+_?=-]+")
        # Replace invalid character ranges with a "-"
        (concatMapStrings (s:
          if args.nixpkgs.lib.isList s
          then "_"
          else s))
        (x: substring (args.nixpkgs.lib.max (stringLength x - 207) 0) (-1) x)
        (x:
          if stringLength x == 0
          then "unknown"
          else x)
      ];

  /*
   Like `mapAttrsRecursiveCond`, but the condition can examine the path
   */
  mapAttrsRecursiveCondFunc = with builtins;
    mapper: cond: f: set: let
      recurse = path: let
        g = name: value: let
          path' = path ++ [name];
          try =
            builtins.tryEval
            (
              if isAttrs value && cond path' value
              then recurse path' value
              else f path' value
            );
        in
          if try.success
          then try.value
          else null;
      in
        mapper g;
    in
      recurse [] set;

  /*
   Like `mapAttrsRecursiveCond`, but the condition can examine the path
   */
  mapAttrsRecursiveCond = self.lib.mapAttrsRecursiveCondFunc builtins.mapAttrs;
  mapAttrsRecursiveList = self.lib.mapAttrsRecursiveCondFunc args.nixpkgs.lib.mapAttrsToList;

  nixpkgsRecurseFunc = self.lib.nixpkgsRecurseFuncWith args.nixpkgs;
  nixpkgsRecurseFuncWith = pkgs: func:
    pkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] (system:
      pkgs.lib.genAttrs self.__stabilities (stability: (
        self.lib.mapAttrsRecursiveCond
        (path: a:
          (a.recurseForDerivations or false || a.recurseForRelease or false) && !(a ? type && a.type == "derivation"))
        (path: value: func path value stability)
        (import args.${stability} {
          inherit system;
          #config.allowAliases = false;
          config.allowUnfree = true;
        })
      )));

  toNested = with builtins;
  with args.nixpkgs;
    i: let
      raw = lib.splitString "." (i.attrPath or i.attr);
      stripQuotes = replaceStrings [''"''] [""];
      result =
        foldl' (
          acc: i:
            if lib.length acc > 0 && lib.isList (lib.last acc)
            then
              if !isNull (match ''.*("+)$'' i)
              then lib.init acc ++ [(concatStringsSep "_" (lib.last acc ++ [(stripQuotes i)]))]
              else lib.init acc ++ [(lib.last acc ++ [(stripQuotes i)])]
            else if !isNull (match ''^("+).*'' i)
            then acc ++ [[(stripQuotes i)]]
            else acc ++ [i]
        ) []
        raw;
    in
      lib.attrsets.setAttrByPath (lib.drop 2 result) i;

    parsePath = with builtins;
    with args.nixpkgs;
    with args.nixpkgs.lib;
      attrPath: let
        raw = splitString "." attrPath;
        stripQuotes = replaceStrings [''"''] [""];
        result =
          foldl' (
            acc: i:
              if length acc > 0 && isList (last acc)
              then
                if !isNull (match ''.*("+)$'' i)
                then init acc ++ [(concatStringsSep "." (last acc ++ [(stripQuotes i)]))]
                else init acc ++ [(last acc ++ [(stripQuotes i)])]
              else if !isNull (match ''^("+).*'' i)
              then acc ++ [[(stripQuotes i)]]
              else acc ++ [i]
          ) []
          raw;
      in
        result;

    makeApps = nixpkgs:
      with nixpkgs;
        lib.genAttrs ["x86_64-linux"] (system:
          with legacyPackages.${system}; let
            toApp = name: attrs: text: {
              type = "app";
              program = (writeShellApplication ({inherit name text;} // attrs)).outPath + "/bin/${name}";
            };
          in {
            # Run nix-eval-jobs over the first argument
            # TODO: replaced by pure build?
            eval =
              toApp "eval" {
                runtimeInputs = [coreutils args.nix-eval-jobs.defaultPackage.${system} jq];
              } ''
                IFS="#" read -r ref frag <<<"$1"
                ref=$(echo "$ref" | tr '/:' '__')
                mkdir -p output
                nix-eval-jobs --flake "$1" --depth 2 | tee output/full.json
                jq -s '.[]' < full.json > output/"$ref"#"$frag".json
              '';

            checkCache =
              toApp "checkCache" {
                runtimeInputs = [coreutils args.nix-eval-jobs.defaultPackage.${system} jq parallel sqlite]; # {{{
              } ''

                 #wrapping parallel curl of narinfo url
                 function cached_curl(){
                   storepath="$1"
                   query="select id,built from cache where id='$1'"
                   result=$(sqlite3 "$DB" "$query")
                   rid=$(echo "$result" | cut -d'|' -f1)
                   rbool=$(echo "$result" | cut -d'|' -f2)
                   #printf '%s' "%% $rid  %% - %% $rbool %%"
                   if  [[ "$rid" = "$storepath" ]]
                   then
                     update_existing_record
                   else
                     add_to_cache
                   fi
                 }

                 function update_existing_record(){
                   if [[ "$rbool" = "0" ]]
                   then
                     printf "%s" "ALERADY IN CACHE AND NOT BUILT - FULL QUERY RESULT $result"
                     rereq=$(curl -s -o /dev/null -w "%{http_code}" "https://cache.nixos.org/$storepath.narinfo")
                     if [[ "$rereq" == "404" ]]
                     then
                        timestamp=$(date +"%s")
                        printf "%s\n" "UPDATE cache SET built = 0,last_mod = $timestamp, last_accessed = $timestamp WHERE id='$storepath';" >> tmpcacheupdate.sql
                     elif [[ "$rereq" == "200" ]]
                     then
                        timestamp=$(date +"%s")
                        printf "%s\n" "UPDATE cache SET built = 1,last_mod = $timestamp, last_accessed = $timestamp WHERE id='$storepath';" >> tmpcacheupdate.sql
                     fi
                   fi

                }

                function add_to_cache(){
                   echo "$storepath not in cache"
                   req=$(curl -s -o /dev/null -w "%{http_code}" "https://cache.nixos.org/$storepath.narinfo")
                   printf '%s' "RETURNS $req"
                   if [[ $req == "200" ]]
                   then
                     timestamp=$(date +"%s")
                     printf "%s\n" "$storepath,1,$timestamp,$timestamp" >> tmpcache.csv
                   elif [[ $req == "404" ]]
                   then
                     timestamp=$(date +"%s")
                     printf "%s\n" "$storepath,0,$timestamp,$timestamp" >> tmpcache.csv
                   fi
                }
                 #helper function to create db
                 function create_cache_db(){
                   create_table_sql="create table if not exists cache (id TEXT PRIMARY KEY,built INTEGER,last_mod INTEGER, last_accessed INTEGER);"
                   sqlite3 "$DB" "$create_table_sql"
                 }

                 #db init function
                 function db_init(){
                   if [[ ! -e "$DB" ]]; then
                       create_cache_db
                   fi
                 }
                 export -f add_to_cache cached_curl create_cache_db db_init update_existing_record
                 export FILE="$1"
                 export DB="$2"
                 db_init
                 printf "%s" "BEGIN TRANSACTION;" >> tmpcacheupdate.sql
                 if [ -e "nixpkgs/$FILE" ]
                 then
                   echo "$(<nixpkgs/"$FILE")" | \
                   jq .storePaths[]? | \
                   cut -d/ -f4 | \
                   cut -d- -f1 | \
                   parallel cached_curl
                   if [ -e "tmpcache.csv" ]
                   then
                     sqlite3 "$DB" ".mode csv" ".import tmpcache.csv cache"
                     rm tmpcache.csv
                   fi

                   printf "%s" "COMMIT;" >> tmpcacheupdate.sql
                   if [ -e "tmpcacheupdate.sql" ]
                   then
                     sqlite3 "$DB" < tmpcacheupdate.sql
                     rm tmpcacheupdate.sql
                   fi
                 else
                   echo "JSON file $FILE not found!"
                 fi

              '';

            # }}}
            }); 

      # # Convert DB to versioned structure and write as derivation
      # legacyPackages = args.nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system: {
      #   versionsJSON = let
      #     pkgs = args.nixpkgs.legacyPackages.${system};
      #   in
      #     pkgs.runCommandLocal "versions.json" {
      #       passAsFile = ["text"];
      #       text = builtins.toJSON self.packages.${system}.full-eval;
      #     } ''
      #       cat "$textPath" | ${pkgs.jq}/bin/jq > $out
      #     '';
      #   }
    # // args.nixpkgs.lib.genAttrs self.stabilities (stability:
      # args.nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] (system: {
      #   full-eval = with args.nixpkgs.legacyPackages.${system};
      #     runCommand "full-eval" {
      #       nativeBuildInputs = [
      #         nixUnstable
      #         jq
      #         args.nix-eval-jobs.defaultPackage.${system}
      #       ];
      #     } ''
      #       export HOME=$PWD
      #       export GC_DONT_GC=1
      #       export NIX_CONFIG="experimental-features = flakes nix-command
      #       store = $PWD/temp"
      #       mkdir temp gc $out
      #       nix-eval-jobs --gc-roots-dir $PWD/gc \
      #         --flake ${args.${stability}}#legacyPackages.${system} \
      #         --depth 2 \
      #         | jq -c '.originalUri = "${stability}" |
      #                  .uri = "${builtins.dirOf inputs.${stability}.url}/${args.${stability}.rev}"' \
      #         | tee /dev/fd/2 | jq -cs '{elements:.,version:1}' > $out/manifest.json
      #     '';
      #   })));
    
}
