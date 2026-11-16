// Vercel function: every request is rewritten here (see vercel.json) and handed to Nest.
const { handler } = require('../dist/serverless');

module.exports = handler;
