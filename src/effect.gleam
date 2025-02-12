import gleam/list
import gleam/option

/// The `Effect` type represents computations that might return early or continue with a value.
/// Each effect specifies:
///
/// 1. The type of the continue value (`msg`)
/// 2. The type of early return value (`early`)
///
/// You can treat `msg` as the happy path.
/// The `early` type is for long jumping.
///
pub opaque type Effect(msg, early) {
  Effect(run: List(fn(Action(msg, early)) -> Nil))
}

/// An `Action` represents how to handle both successful and early return paths of an effect.
///
type Action(msg, early) {
  Action(next: Next(msg), not: Not(early))
}

/// A function that handles the successful path of an effect.
///
pub type Next(msg) =
  fn(msg) -> Nil

/// A function that handles the early return path of an effect.
///
pub type Not(early) =
  fn(early) -> Nil

/// Creates an effect that succeeds with the given value.
///
/// ```gleam
/// let effect: Effect(Int, early) = continue(42)
/// ```
pub fn continue(value: msg) -> Effect(msg, early) {
  Effect(run: [fn(act: Action(msg, early)) { act.next(value) }])
}

/// Creates an effect that returns early with the given value.
///
/// ```gleam
/// let effect: Effect(any, String) = throw("Something went wrong")
/// ```
pub fn throw(value: early) -> Effect(msg, early) {
  Effect(run: [fn(act: Action(msg, early)) { act.not(value) }])
}

/// Creates an effect that wraps a result type. The Ok variant continues and the 
/// Error variant returns early.
///
/// ```gleam
/// let effect: Effect(Int, early) = wrap_result(Ok(5))
/// let effect: Effect(msg, String) = wrap_result(Error("wrong!"))
/// ```
pub fn wrap_result(value: Result(msg, early)) -> Effect(msg, early) {
  case value {
    Ok(msg) -> continue(msg)
    Error(early) -> throw(early)
  }
}

/// Creates an effect that wraps an option type. The Some variant continues and the
/// None variant returns early with the given early value.
///
/// ```gleam
/// let effect: Effect(Int, String) = wrap_option(Some(69), "It should've been Some tho...")
/// let effect: Effect(Int, String) = wrap_option(None, "This is None")
pub fn wrap_option(
  value: option.Option(msg),
  early: early,
) -> Effect(msg, early) {
  case value {
    option.Some(msg) -> continue(msg)
    option.None -> throw(early)
  }
}

/// Creates an effect from a boxed value. Primarly used to unbox Promises but
/// can work with other boxed types.
///
/// ```gleam
/// let value: Value = ...
/// let promise: Promise(Value) = promise.resolve(value)
/// let effect: Effect(Value, early) = unbox(promise, promise.map)
/// ```
pub fn unbox(
  box: box,
  unbox_fn: fn(box, fn(inner) -> Nil) -> any,
) -> Effect(inner, early) {
  Effect(run: [
    fn(action: Action(inner, early)) {
      {
        use inner <- unbox_fn(box)
        action.next(inner)
      }
      Nil
    },
  ])
}

/// Chains together two effects where the second effect depends on the result of the first.
///
/// ```gleam
/// let effect = {
///   use a <- then(get_user())
///   use b <- then(get_posts(a.id))
///   continue(b)
/// }
/// ```
pub fn then(
  effect: Effect(msg_1, early),
  handler: fn(msg_1) -> Effect(msg_2, early),
) -> Effect(msg_2, early) {
  Effect(run: [
    fn(act) {
      let act =
        Action(..act, next: fn(msg_1) {
          let Effect(run: runs) = handler(msg_1)
          list.each(runs, fn(run) { run(act) })
        })

      list.each(effect.run, fn(run) { run(act) })
    },
  ])
}

/// Transforms the successful values of an effect via the handler.
///
/// ```gleam
/// let effect = continue(5)
/// use num: Int <- map(effect)
/// num * 2
/// ```
pub fn map(
  effect: Effect(msg, early),
  handler: fn(msg) -> msg_2,
) -> Effect(msg_2, early) {
  Effect(run: {
    use run <- list.map(effect.run)

    fn(act: Action(msg_2, early)) -> Nil {
      let next = fn(msg: msg) -> Nil {
        let Action(next:, not: _) = act
        msg |> handler |> next
      }

      Action(..act, next:) |> run
    }
  })
}

/// Transforms the early return values of an effect via the handler.
///
/// ```gleam
/// type Msg { Msg(String) }
/// let effect: Effect(msg, String) = throw("some context")
/// let effect: Effect(msg, Msg) = map_early(effect, Msg)
/// ```
pub fn map_early(
  effect: Effect(msg, early),
  handler: fn(early) -> early_2,
) -> Effect(msg, early_2) {
  Effect(run: {
    use run <- list.map(effect.run)

    fn(act: Action(msg, early_2)) -> Nil {
      let not = fn(early: early) -> Nil {
        let Action(next: _, not:) = act
        early |> handler |> not
      }
      Action(..act, not:) |> run
    }
  })
}

/// Creates an effect from a value with a handler to operate on it.
///
/// ```gleam
/// use n: Int <- from(5)
/// ```
pub fn from(
  value: msg_1,
  handler: fn(msg_1) -> Effect(msg_2, early),
) -> Effect(msg_2, early) {
  then(continue(value), handler)
}

/// Creates an effect from a Result, where Ok values are passed to the given function
/// and Error values cause an early return.
///
/// ```gleam
/// let str: String = "123"
/// let result: Result(Int, Nil) = parse_int(str)
/// use num: Int <- from_result(result)
/// ```
pub fn from_result(
  value: Result(msg_1, early),
  handler: fn(msg_1) -> Effect(msg_2, early),
) -> Effect(msg_2, early) {
  case value {
    Ok(msg_1) -> handler(msg_1)
    Error(early) -> throw(early)
  }
}

/// Creates an effect from a Result, where Ok values are passed to the given function
/// and Error values cause an early return.
///
/// Maps the error using the given map_error for the final effect. 
/// Helper combines from_result and result.map_error
pub fn from_result_map_error(
  value: Result(msg_1, early),
  map_error: fn(early) -> early2,
  handler: fn(msg_1) -> Effect(msg_2, early2),
) -> Effect(msg_2, early2) {
  case value {
    Ok(msg_1) -> handler(msg_1)
    Error(early) -> throw(early |> map_error)
  }
}

/// Creates an effect from an Option, where Some values are passed to the given function
/// and None causes an early return.
pub fn from_option(
  value: option.Option(msg_1),
  early: early,
  handler: fn(msg_1) -> Effect(msg_2, early),
) -> Effect(msg_2, early) {
  case value {
    option.Some(msg_1) -> handler(msg_1)
    option.None -> throw(early)
  }
}

/// Creates an effect from a boxed value (like a Promise), using the provided unboxing 
/// function (like promise.map) and operates on the unboxed value via the handler.
///
/// ```gleam
/// let promise: Promise(Result(ok, err))
/// use result: Result(ok, err) <- from_box(promise, promise.map)
/// use ok: ok <- from_result(result)
/// ```
pub fn from_box(
  box: box,
  unbox_fn: fn(box, fn(inner) -> Nil) -> any,
  handler: fn(inner) -> Effect(msg, early),
) -> Effect(msg, early) {
  Effect(run: [
    fn(action: Action(msg, early)) {
      {
        use inner <- unbox_fn(box)
        let Effect(run:) = handler(inner)
        list.each(run, fn(run) { run(action) })
      }
      Nil
    },
  ])
}

/// Handles both paths of an effect, allowing transformation into a new effect
/// with potentially different types.
///
/// ```gleam
/// type ShowState {
///   ShowSuccess(valid)
///   ShowError(err)
/// }
/// 
/// use res: Result(valid, err) <- handle(validate_input(data))
/// case res {
///   Ok(valid) -> continue(ShowSuccess(valid))
///   Error(err) -> continue(ShowError(err))
/// }
/// ```
pub fn handle(
  effect: Effect(msg_1, early_1),
  handler: fn(Result(msg_1, early_1)) -> Effect(msg_2, early_2),
) -> Effect(msg_2, early_2) {
  Effect(run: [
    fn(act) {
      let act =
        Action(
          next: fn(msg_1) {
            let Effect(run: runs) = handler(Ok(msg_1))
            list.each(runs, fn(run) { run(act) })
          },
          not: fn(msg_2) {
            let Effect(run: runs) = handler(Error(msg_2))
            list.each(runs, fn(run) { run(act) })
          },
        )
      list.each(effect.run, fn(run) { run(act) })
    },
  ])
}

/// Type representing the absence of an early return value.
pub type Nothing

/// Executes an effect that is known to be pure (cannot have early returns).
/// The handler only needs to handle the success case.
///
/// ```gleam
/// let effect: Effect(Int, early) = continue(42)
/// use num: Int <- pure(effect)
/// num |> int.to_string |> io.println
/// ```
pub fn pure(effect: Effect(msg, Nothing), handler: fn(msg) -> any) -> Nil {
  let act =
    Action(
      next: fn(msg) {
        handler(msg)
        Nil
      },
      not: fn(_) { panic as "how?" },
    )

  list.each(effect.run, fn(run) { run(act) })
}

/// Executes an effect, handling both paths with a handler.
///
/// ```gleam
/// use res: Result(msg, early) <- perform(effect)
/// case res {
///   Ok(value) -> io.println("Success: " <> value)
///   Error(err) -> io.println("Error: " <> err)
/// }
/// ```
pub fn perform(
  effect: Effect(msg, early),
  handler: fn(Result(msg, early)) -> any,
) -> Nil {
  let act =
    Action(
      next: fn(msg) {
        handler(Ok(msg))
        Nil
      },
      not: fn(early) {
        handler(Error(early))
        Nil
      },
    )

  list.each(effect.run, fn(run) { run(act) })
}
