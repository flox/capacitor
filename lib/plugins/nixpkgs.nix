# capacitor API
{lib,...}:
# user API
# Plugin API
{context, capacitate, originalFlake,...}:

{ 
  legacyPackages = lib.genAttrs context.systems (system: 
    lib.mapAttrs (stability: n: {nixpkgs  = n.legacyPackages.${system};}) context.nixpkgsSeeds
  );
}
