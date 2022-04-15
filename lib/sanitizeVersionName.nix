lib:
# Make the versions attribute safe
# sanitizeVersionName :: String -> String
with builtins;
with lib.strings;
  string:
    lib.pipe string [
      unsafeDiscardStringContext
      # Strip all leading "."
      (x: elemAt (match "\\.*(.*)" x) 0)
      (split "[^[:alnum:]+_?=-]+")
      # Replace invalid character ranges with a "-"
      (concatMapStrings (s:
        if lib.isList s
        then "_"
        else s))
      (x: substring (lib.max (stringLength x - 207) 0) (-1) x)
      (x:
        if stringLength x == 0
        then "unknown"
        else x)
    ]
