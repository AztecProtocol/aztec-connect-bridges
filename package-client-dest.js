const { writeFileSync } = require('fs');

const pkg = {
  name: '@aztec/bridge-clients',
  version: '0.1.0',
};

writeFileSync('./client-dest/package.json', JSON.stringify(pkg, null, '  '));
