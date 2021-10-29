/**
 * Obliterator Filter Function
 * ===========================
 *
 * Function returning a iterator filtering the given iterator.
 */
var Iterator = require('./iterator.js');
var iter = require('./iter.js');

/**
 * Filter.
 *
 * @param  {Iterable} target    - Target iterable.
 * @param  {function} predicate - Predicate function.
 * @return {Iterator}
 */
module.exports = function filter(target, predicate) {
  var iterator = iter(target);

  return new Iterator(function next() {
    var step = iterator.next();

    if (step.done) return step;

    if (!predicate(step.value)) return next();

    return step;
  });
};
