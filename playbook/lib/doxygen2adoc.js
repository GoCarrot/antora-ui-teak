const fs = require('fs');
const path = require('path');

const mapLanguage = {
  'Objective-C' : 'objc',
  'c#' : 'csharp'
}

let cachedSymbols = null;
let doxygen2adoc = null;

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

function doxygen2adoc_init(document) {
  // Get configuration
  let doxygen2adoc = document.getAttribute('doxygen2adoc');
  if (!doxygen2adoc) {
    throw new Error(`doxygen2adoc: No paths configured.`);
  }
  doxygen2adoc = doxygen2adoc[0];

  // Load symbols if not loaded
  if (!cachedSymbols) {
    cachedSymbols = loadAllSymbols(doxygen2adoc);
  }

  return doxygen2adoc;
}

function replaceTargetWithLink(match, target, linkText) {
  // Find symbol
  const [symbolMap, symbol] = doxygen2adoc.strict ?
    findSymbolStrict(target) :
    findSymbol(target);

  // If no symbol found, just return the text
  if (!symbolMap) {
    // if (doxygen2adoc.verbose) {
    //   console.error(`doxygen2adoc_link: Cannot resolve '${target}'`);
    // }
    return match;
  }

  linkText = target; //linkText ? linkText : target;
  return `xref:${symbolMap.antora.name}:ROOT:${symbol.source}.adoc#${symbol.target}[${linkText}]`;
}

function includeForTarget(target, args, doc) {
  // Find symbol
  const [symbolMap, symbol] = doxygen2adoc.strict ?
    findSymbolStrict(target) :
    findSymbol(target);

  if (!symbolMap) {
    return [`**Cannot resolve 'doxygen2adoc:${target}'**`];
  }

  if (!symbol.part) {
    return [`**No part found for: 'doxygen2adoc:${target}'**`];
  }

  args = args ? args : '';

  const includeStatement = `include::${symbolMap.antora.name}:ROOT:${symbol.part}[${args}]`;

  let newLines = [includeStatement];

  // Assign default attributes if missing
  if (!doc.getAttribute('part_decl')) {
    doc.setAttribute('part_decl', undefined);
  }

  const targetLanguage = mapLanguage[symbol.language] || symbol.language.toLowerCase();
  const docSourceLanguage = doc.getAttribute('source-language');
  if (!docSourceLanguage) {
    doc.setAttribute('source-language', targetLanguage);
  } else if (docSourceLanguage !== targetLanguage) {
    newLines = [
      `:source-language: ${targetLanguage}`,
      includeStatement,
      `:source-language: ${docSourceLanguage}`
    ];
  }

  return newLines;
}

module.exports.register = function register (registry) {
  registry.preprocessor(function() {
    const self = this;

    self.process(function (doc, reader) {
      // Global :(
      doxygen2adoc = doxygen2adoc_init(doc);

      if (doxygen2adoc.verbose) {
        console.log(`doxygen2adoc: Reading ${doc.getAttribute('docfile')}`);
      }

      const lines = reader.lines;
      reader.lines = [];

      for (i in lines) {
        const line = lines[i].trim();

        if (line.includes('“') || line.includes('”')) {
          throw new Error(`Smart quotes found in ${doc.getAttribute('docfile')}: ${line}`);
        }

        if (match = line.match(/^doxygen2adoc\:(?<target>.+)\[(?<args>.*?)\]$/)) {
          // doxygen2adoc include, append new lines
          const newLines = includeForTarget(match.groups.target, match.groups.args, doc);
          if (newLines) {
            reader.lines = reader.lines.concat(newLines);
          } else {
            // No new lines returned, push original line
            reader.lines.push(lines[i]);
          }
        } else {
          // Replace
          reader.lines.push(
            lines[i].replaceAll(/<<(?<target>.+)>>/g, replaceTargetWithLink)
          );
        }
      }

      return reader;
    });
  });

  return registry;
}
