import gleam/javascript/promise
import gleam/list
import gleam/option

/// An effect that can produce either an Ok(a) or an Error(e).
/// Use `perform` to execute an Effect, providing a callback that
/// receives the final Result(a, e).
pub opaque type Effect(a, e) {
  Effect(run: List(fn(Actions(a, e)) -> Nil))
}

/// Holds the `dispatch` function used internally by each effect step.
/// Typically you won't create `Actions` directly; it's used by `perform`.
pub type Actions(a, e) {
  Actions(dispatch: fn(Result(a, e)) -> Nil)
}

/// Create an Effect from a callback that manually dispatches Ok or Error.
/// Example:
/// ```gleam
/// from(fn(dispatch) {
///   dispatch(Ok(42))
/// })
/// ```
pub fn from(effect: fn(fn(Result(a, e)) -> Nil) -> Nil) -> Effect(a, e) {
  Effect(run: [fn(actions: Actions(a, e)) { effect(actions.dispatch) }])
}

/// Create an Effect that immediately dispatches a pre-existing Result(a, e).
/// Useful for wrapping a plain result in the effect system.
pub fn from_result(result: Result(a, e)) -> Effect(a, e) {
  Effect(run: [fn(actions: Actions(a, e)) { actions.dispatch(result) }])
}

/// Create an Effect from an option, mapping the None case into the error channel
/// Useful for wrapping an option into the effect system when None is considered an error.
pub fn from_option(opt: option.Option(a), if_none: e) -> Effect(a, e) {
  case opt {
    option.Some(x) -> succeed(x)
    option.None -> fail(if_none)
  }
}

/// Create an Effect that immediately succeeds with value `x`.
/// Shorthand for `from_result(Ok(x))`.
pub fn succeed(x: a) -> Effect(a, e) {
  from(fn(dispatch) { dispatch(Ok(x)) })
}

/// Create an Effect that immediately fails with error `err`.
/// Shorthand for `from_result(Error(err))`.
pub fn fail(err: e) -> Effect(a, e) {
  from(fn(dispatch) { dispatch(Error(err)) })
}

/// Transform the success value in an Effect from type `a` to `b`.
/// The error type `e` is left unchanged.
/// Example:
/// ```gleam
/// succeed(2)
/// |> map(fn(x) { x * 2 })  // Ok(4)
/// ```
pub fn map(effect: Effect(a, e), f: fn(a) -> b) -> Effect(b, e) {
  Effect(
    run: list.map(effect.run, fn(eff) {
      fn(actions: Actions(b, e)) {
        // Internal adaptation
        let adapted_actions =
          Actions(dispatch: fn(result: Result(a, e)) {
            case result {
              Ok(value) -> actions.dispatch(Ok(f(value)))
              Error(err) -> actions.dispatch(Error(err))
            }
          })
        eff(adapted_actions)
      }
    }),
  )
}

/// Transform the error value in an Effect from type `e` to `e2`.
/// The success value `a` is left unchanged.
/// Example:
/// ```gleam
/// fail("Oops!")
/// |> map_error(fn(e) { "Mapped: " <> e })
/// ```
pub fn map_error(effect: Effect(a, e), f: fn(e) -> e2) -> Effect(a, e2) {
  Effect(
    run: list.map(effect.run, fn(eff) {
      fn(actions: Actions(a, e2)) {
        // Internal adaptation
        let adapted_actions =
          Actions(dispatch: fn(result: Result(a, e)) {
            case result {
              Ok(value) -> actions.dispatch(Ok(value))
              Error(err) -> actions.dispatch(Error(f(err)))
            }
          })
        eff(adapted_actions)
      }
    }),
  )
}

/// Chain two Effects. If `effect` succeeds with Ok(a), call `f(a)` to
/// produce a new Effect(b, e). If `effect` fails, propagate the error.
/// Example:
/// ```gleam
/// succeed(2)
/// |> try(fn(x) {
///   if x > 0 { succeed(x * 10) }
///   else { fail("Can't multiply") }
/// })
/// ```
pub fn try(effect: Effect(a, e), f: fn(a) -> Effect(b, e)) -> Effect(b, e) {
  Effect(
    run: list.map(effect.run, fn(eff) {
      fn(actions: Actions(b, e)) {
        // Internal adaptation
        let adapted_actions =
          Actions(dispatch: fn(result: Result(a, e)) {
            case result {
              Ok(value) -> {
                let Effect(run: runs_b) = f(value)
                list.each(runs_b, fn(run_b) { run_b(actions) })
              }
              Error(err) -> actions.dispatch(Error(err))
            }
          })
        eff(adapted_actions)
      }
    }),
  )
}

/// Convert a JavaScript Promise<Result(a, e)> into an Effect(a, e).
/// The Effect will dispatch either Ok(a) or Error(e) based on the
/// resolved promise value.
pub fn from_promise(pres: promise.Promise(Result(a, e))) -> Effect(a, e) {
  Effect(run: [
    fn(actions: Actions(a, e)) {
      promise.map(pres, fn(res) {
        actions.dispatch(res)
        Nil
      })
      Nil
    },
  ])
}

/// Wait on `pres` (a Promise<Result(a, e)>) and then,
/// if it succeeds with Ok(a), run `f(a)`.
/// Otherwise, dispatch Error(e).
pub fn try_await(
  pres: promise.Promise(Result(a, e)),
  f: fn(a) -> Effect(b, e),
) -> Effect(b, e) {
  from_promise(pres)
  |> try(f)
}

/// Like `try_await`, but first map the error using `f_err`.
/// If the promise fails with Error(e), transform it into Error(e2),
/// then call `f` if successful.
pub fn try_await_map_error(
  pres: promise.Promise(Result(a, e)),
  f_err: fn(e) -> e2,
  f: fn(a) -> Effect(b, e2),
) -> Effect(b, e2) {
  from_promise(pres)
  |> map_error(f_err)
  |> try(f)
}

/// Execute an Effect by supplying the final callback to handle
/// the Result(a, e). Use this to “run” the effect.
/// Example:
/// ```gleam
/// let eff = succeed(10)
/// perform(eff, fn(res) {
///   case res {
///     Ok(value) -> io.println("Got: \(value)")
///     Error(e)  -> io.println("Error: \(e)")
///   }
/// })
/// ```
pub fn perform(effect: Effect(a, e), callback: fn(Result(a, e)) -> Nil) -> Nil {
  let actions = Actions(dispatch: callback)
  list.each(effect.run, fn(run) { run(actions) })
}

