# split.jq takes a list of elements and creates a nested object based on the
# element's attrPath split by "."
# Expected Usage: nix-eval-jobs --flake .#legacyPackages.x86_64-linux | head | jq -sf split.jq

.|map(select(.active == true)|. as $j |
    {}| ($j.attrPath|split(".")) as $p | setpath($p;{
        outPath:($j|.storePaths[-1]),
        element:$j
    }))|reduce .[] as $x ({}; . * $x)
