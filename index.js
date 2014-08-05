var cs = require('coffee-script');
if (typeof cs.register === 'function') {
	cs.register();
}
module.exports = require('./lib/steady');
