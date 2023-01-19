context' @ {
  system,
  nixpkgs,
  self,
  /*
  inputs as in `context` but with attributes for other systems removed

  context.inputs.<input>.<attribute>.<~~system~~>.*
  */
  # TODO: not recursive
  inputs,
  /*
  capacitated as in `context` but with attributes for other systems removed

  context.inputs.<input>.<attribute>.<~~system~~>.*
  */
  capacitated,
  /*
  closures:: type -> [closure']

  function to list all closures of a `type`, e.g. `pacakges` or `lib`, ...
  that are defined for `system`
  */
  # TODO: does not work for systems other than the configured ones
  closures,
  /*
  callPackage to call function with with instantiated nixpkgs and context
  */
  callPackageWith,
}:
context'
