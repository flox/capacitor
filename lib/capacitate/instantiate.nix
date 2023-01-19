# TODO: replace with sanitize or remove
{lib}: system: inputs:
lib.mapAttrs (
  _: flakeInput:
    flakeInput.${system} or flakeInput
)
inputs
