# Override originalUri and uri output from nix-eval-jobs
# Expected Usage:
# nix-eval-jobs --flake .#legacyPackages.x86_64-linux | \
# jq \
# --arg originalUri "github:flox/nixpkgs-flox" \
# --arg uri "github:flox/nixpkgs-flox/5faba6fb75705383e6eda2014d30a5a231adced9" \
# -f fixup.jq

. +=
{
"originalUri": $originalUri,
"uri": $uri
}
