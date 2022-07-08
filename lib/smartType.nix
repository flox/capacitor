{lib,...}: attrpkgs:
attrpkgs.type
or (
  if lib.isFunction attrpkgs
  then "lambda"
  else builtins.typeOf attrpkgs
)
