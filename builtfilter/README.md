# Builtfilter

## Usage
```
cat manifest.json | jq .elements[] -c | go run ./builtfilter/main.go grep -d cache.db
```

Using [modified nix-eval-jobs](github.com/flox/nix-eval-jobs)
```
nix-eval-jobs --flake . | go run ./builtfilter/main.go grep -d cache.db
```
