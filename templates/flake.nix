{
  outputs = {self, ...}: let
    db = with builtins; fromJSON (readFile ./pkgs.json);
  in {
    lib = with builtins; rec {
      # {{{
      range =
        # First integer in the range
        first:
        # Last integer in the range
        last:
          if first > last
          then []
          else genList (n: first + n) (last - first + 1);
      stringToCharacters = s:
        map (p: substring p 1 s) (self.lib.range 0 (stringLength s - 1));

      replaceChars =
        builtins.replaceStrings
        or (
          del: new: s: let
            substList = lib.zipLists del new;
            subst = c: let
              found = lib.findFirst (sub: sub.fst == c) null substList;
            in
              if found == null
              then c
              else found.snd;
          in
            stringAsChars subst s
        );
      escape = list: replaceChars list (map (c: "\\${c}") list);
      escapeRegex = escape (stringToCharacters "\\[{()^$?*+|.");

      sublist =
        # Index at which to start the sublist
        start:
        # Number of elements to take
        count:
        # Input list
        list: let
          len = length list;
        in
          genList
          (n: elemAt list (n + start))
          (
            if start >= len
            then 0
            else if start + count > len
            then len - start
            else count
          );
      take =
        # Number of elements to take
        count: sublist 0 count;
      init = list:
        assert (list != []);
          take (length list - 1) list;
      last = list:
        assert (list != []);
          elemAt list (length list - 1);
      addContextFrom = a: b: substring 0 0 a + b;
      splitString = _sep: _s: let
        sep = builtins.unsafeDiscardStringContext _sep;
        s = builtins.unsafeDiscardStringContext _s;
        splits = builtins.filter builtins.isString (builtins.split (escapeRegex sep) s);
      in
        map (v: addContextFrom _sep (addContextFrom _s v)) splits;
      recurseIntoAttrs = attrs: attrs // {recurseForDerivations = true;};
      setAttrByPath = attrPath: value: let
        len = length attrPath;
        atDepth = n:
          if n == len
          then value
          else {${elemAt attrPath n} = atDepth (n + 1);};
      in
        atDepth 0;

      getAttrFromPath = attrPath: let
        errorMsg = "cannot find attribute `" + concatStringsSep "." attrPath + "'";
      in
        attrByPath attrPath (abort errorMsg);

      attrByPath = attrPath: default: e: let
        attr = head attrPath;
      in 
        if attrPath == []
        then e
        else if e ? ${attr}
        then attrByPath (tail attrPath) default e.${attr}
        else default;

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

      parsePath = with builtins;
      with self.lib;
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

      toNested = with builtins;
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
          self.lib.setAttrByPath (lib.drop 2 result) i;
    }; # }}}

    legacyPackages = builtins.mapAttrs (system: v:
      self.lib.mapAttrsRecursiveCondFunc
      (func: x: self.lib.recurseIntoAttrs (builtins.mapAttrs func x))
      (path: a: !(builtins.isAttrs a && a ? outPath))
      (
        _: x:
        ### Three approaches to bring in a fake derivation
        let
          # mkFakeDerivation
          # cons: cannot be used as a top-level build target
          # pros: simple, uses existing primitives
          storePath = {
            type = "derivation";
            outPath = builtins.storePath x.outPath;
            drvPath = x.element.drvPath;
          };

          # wrapped fake derivation
          # cons: requires multi-step usage at CLI
          # pros: allowed to be used at top-level
          wrapper = derivation {
            name = "wrapper";
            inherit system;
            builder = "builtin:buildenv";
            manifest = storePath.outPath;
            derivations = map (x: ["true" 5 1 x]) [storePath];
          };

          # builtins.getFlake
          # cons: slower evaluation, depends on another nixpkgs download
          # pros: simple and allowed at top-level
          theFlake = builtins.getFlake x.element.uri;
          theAttr =
          (
            self.lib.getAttrFromPath
            (self.lib.parsePath x.element.attrPath)
            theFlake
            );
        in
        ({
            set = theAttr;
            lambda = theAttr {};
          }.${builtins.typeOf theAttr}
          )
          //
          # Use these overrides to avoid evaluating each attr via getFlake
          (let
            # TODO: this is not quite true
            path = self.lib.parsePath x.element.attrPath;
          in
          {
            # TODO: have nix-eval-jobs retain meta data?
            # - [ ] retain description
            # - [ ] retain name
            # - [ ] retain pname
            # - [ ] retain version
            type = "derivation";
            name = self.lib.last path;
            pname = self.lib.last path;
            version = x.element.attrPath;
            outPath = x.outPath;
            meta.flakeref = "${x.element.uri}#${x.element.attrPath}";
          })
      )
      v
      )
      db.legacyPackages;
  };
}
