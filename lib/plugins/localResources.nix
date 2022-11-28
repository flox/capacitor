# capacitor API
{lib, ...}:
# user API
{
  type,
  path ? [type],
  injectedArgs ? {},
  dir ? type,
}:
# Plugin API
{context, ...}: {
  __reflect.finalFlake = lib.setAttrByPath path (context.auto.localResourcesWith injectedArgs type context "${dir}/");
}
