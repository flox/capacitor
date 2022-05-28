rec {
  # check pkgs.vscode-extensions ? extension
  isNixpkgsExtension = pkgs: extension:
    pkgs.lib.attrsets.hasAttrByPath (pkgs.lib.splitString "." extension)
    pkgs.vscode-extensions;

  nixpkgsExtensions = pkgs: extensions:
    builtins.map (extensionStr:
      pkgs.lib.attrsets.getAttrFromPath (pkgs.lib.splitString "." extensionStr)
      pkgs.vscode-extensions)
    (builtins.filter (isNixpkgsExtension pkgs) extensions);

  # generate a list of full attribute paths for each extension string
  configuredVscode = pkgs: vscodeConfig: lockedMarketplaceExtensions:
    if vscodeConfig ? extensions then
      pkgs.vscode-with-extensions.override {
        vscodeExtensions = (nixpkgsExtensions pkgs vscodeConfig.extensions)
          ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace lockedMarketplaceExtensions;
      }
    else
      pkgs.vscode;

  marketplaceExtensionStrs = pkgs: extensions:
    builtins.filter (extension: !(isNixpkgsExtension pkgs) extension)
    extensions;
}

