(* Copyright (C) 2009 Matthew Fluet.
 * Copyright (C) 1999-2008 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

structure Control: CONTROL =
struct

open ControlFlags

structure Verbosity =
   struct
      datatype t = datatype verbosity

      val op <= =
         fn (Silent, _) => true
          | (Top, Silent) => false
          | (Top, _) => true
          | (Pass, Pass) => true
          | (_, Detail) => true
          | _ => false
   end

datatype style = No | Assembly | C | Dot | ML

val preSuf =
   fn No => ("", "")
    | Assembly => ("/* ", " */")
    | C => ("/* ", " */")
    | Dot => ("// ", "")
    | ML => ("(* ", " *)")

fun outputHeader (style: style, output: Layout.t -> unit) =
   let
      val (pre, suf) = preSuf style
      val lines =
         Version.banner
         :: concat ["  created this file on ", Date.toString (Date.now ()), "."]
         :: "Do not edit this file."
         :: "Flag settings: "
         :: (List.map (all (), fn {name, value} =>
                       concat ["   ", name, ": ", value]))
   in List.foreach (lines, fn l => output (Layout.str (concat [pre, l, suf])))
   end

fun outputHeader' (style, out: Out.t) =
   outputHeader (style, fn l =>
                 (Layout.output (l, out);
                  Out.newline out))

val depth: int ref = ref 0
fun getDepth () = !depth
fun indent () = depth := !depth + 3
fun unindent () = depth := !depth - 3

fun message (verb: Verbosity.t, th: unit -> Layout.t): unit =
   if Verbosity.<= (verb, !verbosity)
      then let
              val out = Out.error
              val lay = th ()
           in
              if Layout.isEmpty lay
                 then ()
              else (Layout.output (Layout.indent (lay, !depth), out)
                    ; Out.newline out)
           end
   else ()

fun messageStr (verb, s: string): unit =
   message (verb, fn () => Layout.str s)

fun time () =
   let
      open Time
      val {children, self, gc, ...} = times ()
      fun add {utime, stime} = utime + stime
   in
      (add self + add children, add gc)
   end

fun timeToString {total, gc} =
   let
      fun fmt (x, n) = Real.format (x, Real.Format.fix (SOME n))
      val toReal = Real.fromIntInf o Time.toMilliseconds
      val per =
         if Time.equals (total, Time.zero)
            then "0"
         else fmt (100.0 * (toReal gc / toReal total), 0)
      fun t2s t =
         fmt (Real./ (toReal t, 1000.0), 2)
   in concat [t2s (Time.- (total, gc)), " + ", t2s gc, " (", per, "% GC)"]
   end

fun trace (verb, name: string) (f: 'a -> 'b) (a: 'a): 'b =
   if Verbosity.<= (verb, !verbosity)
      then
         let
            val _ = messageStr (verb, concat [name, " starting"])
            val (t, gc) = time ()
            val _ = indent ()
            fun done () =
               let
                  val _ = unindent ()
                  val (t', gc') = time ()
               in
                  timeToString {total = Time.- (t', t),
                                gc = Time.- (gc', gc)}
               end
         in (f a
             before messageStr (verb, concat [name, " finished in ", done ()]))
            handle e =>
               (messageStr (verb, concat [name, " raised in ", done ()])
                ; (case Exn.history e of
                      [] => ()
                    | history =>
                         (messageStr (verb, concat [name, " raised with history: "])
                          ; (List.foreach
                             (history, fn s =>
                              messageStr (verb, concat ["\t", s])))))
                ; raise e)
         end
   else
      f a

type traceAccum = {verb: verbosity, 
                   total: Time.t ref, 
                   totalGC: Time.t ref}

val traceAccum: (verbosity * string) -> (traceAccum * (unit -> unit)) =
   fn (verb, name) =>
   let
     val total = ref Time.zero
     val totalGC = ref Time.zero
   in
     ({verb = verb, total = total, totalGC = totalGC},
      fn () => messageStr (verb,
                           concat [name, 
                                   " totals ",
                                   timeToString
                                   {total = !total,
                                    gc = !totalGC}]))
   end

val ('a, 'b) traceAdd: (traceAccum * string) -> ('a -> 'b) -> 'a -> 'b =
   fn ({verb, total, totalGC}, name) =>
   fn f =>
   fn a =>
   if Verbosity.<= (verb, !verbosity)
     then let
            val (t, gc) = time ()
            fun done () 
              = let
                  val (t', gc') = time ()
                in
                  total := Time.+ (!total, Time.- (t', t))
                  ; totalGC := Time.+ (!totalGC, Time.- (gc', gc))
                end
          in
            (f a
             before done ())
            handle e => 
               (messageStr (verb, concat [name, " raised"])
                ; (case Exn.history e of
                      [] => ()
                    | history =>
                         (messageStr (verb, concat [name, " raised with history: "])
                          ; (List.foreach
                             (history, fn s =>
                              messageStr (verb, concat ["\t", s])))))
                ; raise e)
          end
     else f a

val ('a, 'b) traceBatch: (verbosity * string) -> ('a -> 'b) ->
                         (('a -> 'b) * (unit -> unit)) =
   fn (verb, name) =>
   let
     val (ta,taMsg) = traceAccum (verb, name)
   in
     fn f =>
     (traceAdd (ta,name) f, taMsg)
   end

(*------------------------------------*)
(*               Errors               *)
(*------------------------------------*)

val numErrors: int ref = ref 0

val errorThreshhold: int ref = ref 20

val die = Process.fail

local
   fun msg (kind: string, r: Region.t, msg: Layout.t, extra: Layout.t): unit =
      let
         open Layout
         val p =
            case Region.left r of
               NONE => "<bogus>"
             | SOME p => SourcePos.toString p
         val msg = Layout.toString msg
         val msg =
            Layout.str
            (concat [String.fromChar (Char.toUpper (String.sub (msg, 0))),
                     String.dropPrefix (msg, 1),
                     "."])
         in
            outputl (align [seq [str (concat [kind, ": "]), str p, str "."],
                            indent (align [msg,
                                           indent (extra, 2)],
                                    2)],
                     Out.error)
      end
in
   fun warning (r, m, e) = msg ("Warning", r, m, e)
   fun error (r, m, e) =
      let
         val _ = Int.inc numErrors
         val _ = msg ("Error", r, m, e)
      in
         if !numErrors = !errorThreshhold
            then die "compilation aborted: too many errors"
         else ()
      end
end

fun errorStr (r, msg) = error (r, Layout.str msg, Layout.empty)

fun checkForErrors (name: string) =
   if !numErrors > 0
      then die (concat ["compilation aborted: ", name, " reported errors"])
   else ()

fun checkFile (f: File.t, {fail: string -> 'a, name, ok: unit -> 'a}): 'a = let
   fun check (test, msg, k) =
      if test f then
         k ()
      else
         fail (concat ["File ", name, " ", msg])
   in
      check (File.doesExist, "does not exist", fn () =>
             check (File.canRead, "cannot be read", ok))
   end

(*---------------------------------------------------*)
(*                  Compiler Passes                  *)
(*---------------------------------------------------*)

datatype 'a display =
   NoDisplay
  | Layout of 'a -> Layout.t
  | Layouts of 'a * (Layout.t -> unit) -> unit

fun 'a sizeMessage (name: string, a: 'a): Layout.t =
   let open Layout
   in str (concat [name, " size = ",
                   Int.toCommaString (MLton.size a), " bytes"])
   end

val diagnosticWriter: (Layout.t -> unit) option ref = ref NONE

fun diagnostics f =
   case !diagnosticWriter of
      NONE => ()
    | SOME w => f w

fun diagnostic f = diagnostics (fn disp => disp (f ()))

fun saveToFile ({suffix: string},
                style,
                a: 'a,
                d: 'a display): unit =
   let
      fun doit f =
         trace (Pass, "display")
         Ref.fluidLet
         (inputFile, concat [!inputFile, ".", suffix], fn () =>
          File.withOut (!inputFile, fn out =>
                        f (fn l => (Layout.outputl (l, out)))))
   in
      case d of
         NoDisplay => ()
       | Layout layout =>
            doit (fn output =>
                  (outputHeader (style, output)
                   ; output (layout a)))
       | Layouts layout =>
            doit (fn output =>
                  (outputHeader (style, output)
                   ; layout (a, output)))
   end

fun maybeSaveToFile ({name: string, suffix: string},
                     style: style,
                     a: 'a,
                     d: 'a display): unit =
   if not (List.exists (!keepPasses, fn re =>
                        Regexp.Compiled.matchesAll (re, name)))
      then ()
   else saveToFile ({suffix = concat [name, ".", suffix]}, style, a, d)

fun pass {display: 'a display,
          name: string,
          suffix: string,
          stats: 'a -> Layout.t,
          style: style,
          thunk: unit -> 'a}: 'a =
   let
      val result = 
         if not (List.exists (!diagPasses, fn re =>
                              Regexp.Compiled.matchesAll (re, name)))
            then trace (Pass, name) thunk ()
         else
            let
               val result = ref NONE
               val _ =
                  saveToFile
                  ({suffix = concat [name, ".diagnostic"]}, No, (),
                   Layouts (fn ((), disp) =>
                            (diagnosticWriter := SOME disp
                             ; result := SOME (trace (Pass, name) thunk ())
                             ; diagnosticWriter := NONE)))
            in
               valOf (!result)
            end
      val verb = Detail
      val _ = message (verb, fn () => Layout.str (concat [name, " stats"]))
      val _ = indent ()
      val _ = message (verb, fn () => sizeMessage (suffix, result))
      val _ = message (verb, fn () => stats result)
      val _ = message (verb, PropertyList.stats)
      val _ = message (verb, HashSet.stats)
      val _ = unindent ()
      val _ = checkForErrors name
      val _ = maybeSaveToFile ({name = name, suffix = suffix},
                               style, result, display)
   in
      result
   end

(* Code for diagnosing a pass. *)
val pass =
   fn z as {name, ...} =>
   if MLton.Profile.isOn
      then if not (List.exists (!profPasses, fn re =>
                                Regexp.Compiled.matchesAll (re, name)))
              then pass z
           else let
                   open MLton.Profile
                   val d = Data.malloc ()
                   val result = withData (d, fn () => pass z)
                   val _ = Data.write (d, concat [!inputFile, ".", name, ".mlmon"])
                   val _ = Data.free d
                in
                   result
                end
   else pass z

fun passTypeCheck {display: 'a display,
                   name: string,
                   stats: 'a -> Layout.t,
                   style: style,
                   suffix: string,
                   thunk: unit -> 'a,
                   typeCheck = tc: 'a -> unit}: 'a =
   let
      val result = pass {display = display,
                         name = name,
                         stats = stats,
                         style = style,
                         suffix = suffix,
                         thunk = thunk}
      val _ =
         if !typeCheck
            then trace (Pass, "typeCheck") tc result
         else ()
   in
      result
   end

end
