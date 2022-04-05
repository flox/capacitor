values:
with builtins; (
  sort (a: b:
    isAttrs a
    && isAttrs b
    && a ? version
    && builtins.isString a.version
    && b ? version
    && builtins.isString b.version
    && compareVersions a.version b.version >= 0)
  values
)
