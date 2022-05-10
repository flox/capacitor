# Usage

```shell
nix eval ~/flox/flox-examples/teampkgs#__reflect.analysis.packages --json | jq -cr .[] | cargo run -- | jq
```
