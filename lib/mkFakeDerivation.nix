# mkFakeDerivation transforms data in catalog format into a fake derivation with a store path that
# can be substituted
{...}: element: let
  outputs = element.eval.outputs or (throw "unable to create mkFakeDerivation: no eval.outputs");
  outputNames = builtins.attrNames outputs;
  defaultOutput = builtins.head outputNames;
  common =
    {
      name = element.eval.name or "unnamed";
      version = element.eval.version or null;
      pname = element.eval.pname or null;
      meta = element.eval.meta or {};
      system = element.eval.system or {};
    }
    // outputsSet
    //
    # We want these attributes to have higher precedence than outputsSet since they are critical to
    # the use of the result, and a "type", "all", or "outputs" attribute in outputsSet could override
    # these attributes.
    # Even if "type", "all", or "outputs" from outputsSet get overriden, they will still be accessible
    # via the "all" attirbute below since this is a recursive structure
    {
      type = "derivation";
      outputs = outputNames;
      all = outputsList;
    };
  outputToAttrListElement = outputName: {
    name = outputName;
    value =
      common
      // rec {
        inherit outputName;
        outPath = builtins.storePath outputs.${outputName};
      };
  };
  outputsList = map outputToAttrListElement outputNames;
  outputsSet = builtins.listToAttrs outputsList;
in
  outputsSet.${defaultOutput}
