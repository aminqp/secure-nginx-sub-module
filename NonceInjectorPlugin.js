const HtmlWebpackPlugin = require('html-webpack-plugin');

// Create a simple NonceInjector plugin
class NonceInjectorPlugin {
  apply(compiler) {
    compiler.hooks.compilation.tap('NonceInjectorPlugin', (compilation) => {
      HtmlWebpackPlugin.getHooks(compilation).alterAssetTags.tapAsync(
          'NonceInjectorPlugin',
          (data, callback) => {
            // Add nonce to all scripts and styles
            data.assetTags.scripts.forEach(tag => {
              tag.attributes.nonce = '__CSP_NONCE__';
            });
            data.assetTags.styles.forEach(tag => {
              tag.attributes.nonce = '__CSP_NONCE__';
            });
            callback(null, data);
          },
      );
    });
  }
}

// Add to webpack plugins array
plugins: [
  // ... other plugins
  new NonceInjectorPlugin(),
];
