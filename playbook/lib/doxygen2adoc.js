const fs = require('fs');
const path = require('path');

let cachedSymbols = null;

function loadAllSymbols(doxygen2adoc) {
  const ret = [];
  const symbolPaths = doxygen2adoc.symbols;
  for (const i in symbolPaths) {
    const symbolPath = path.resolve(`${__dirname}/../${symbolPaths[i]}`);
    try {
      if (doxygen2adoc.verbose) {
        console.log(`doxygen2adoc: Loading symbols from '${symbolPath}'`);
      }
      const sym = JSON.parse(fs.readFileSync(symbolPath, 'utf-8'));
      ret.push(sym);
    } catch(ignored) {
      console.warn(`doxygen2adoc: Could not find symbols at '${symbolPath}'`)
    }
  }
  return ret;
}

function findSymbolStrict(symbol) {
  for (let i in cachedSymbols) {
    if (cachedSymbols[i].symbols[symbol]) {
      return [cachedSymbols[i], cachedSymbols[i].symbols[symbol]];
    }
  }

  return [null, null];
}

function findSymbol(symbol) {
  for (let i in cachedSymbols) {
    for (let [key, value] of Object.entries(cachedSymbols[i].symbols)) {
      if (key.endsWith(symbol)) {
        return [cachedSymbols[i], value];
      }
    }
  }

  return [null, null];
}

function doxygenInlineMacro () {
  const self = this;
  self.named('@doxygen2adoc');
  self.match(/\[\[(?<target>.+)\]\]/);

  self.process(function (parent, target, attrs) {
    const originalValue = `[[${target}]]`;
    const requestedSymbol = target.replaceAll('&lt;', '<').replaceAll('&gt;', '>');

    // Get configuration
    let doxygen2adoc = parent.document.attributes.$$smap['doxygen2adoc'];
    if (!doxygen2adoc) {
      console.error(`doxygen2adoc: No paths configured. Cannot resolove '${requestedSymbol}'`);
      return originalValue;
    }
    doxygen2adoc = doxygen2adoc[0];

    // Load symbols if not loaded
    if (!cachedSymbols) {
      cachedSymbols = loadAllSymbols(doxygen2adoc);
    }

    // Find symbol
    const [symbolMap, symbol] = doxygen2adoc.strict ?
      findSymbolStrict(requestedSymbol) :
      findSymbol(requestedSymbol);

    // If no symbol found, just return the text
    if (!symbolMap) {
      if (doxygen2adoc.verbose) {
        console.error(`doxygen2adoc: Cannot resolove '${requestedSymbol}'`);
      }
      return originalValue;
    }

    // Turn into a link
    const link = `/${symbolMap.antora.name}/${symbolMap.antora.version}/${symbol.source}.html#${symbol.target}`;

    return this.createInline(parent, 'anchor', target, {
      type: 'link',
      target: link
    });
  })
}

module.exports.register = function register (registry) {
  if (typeof registry.register === 'function') {
    registry.register(function () {
      this.inlineMacro(doxygenInlineMacro);
    });
  } else if (typeof registry.block === 'function') {
    registry.inlineMacro(doxygenInlineMacro);
  }
  return registry;
}
