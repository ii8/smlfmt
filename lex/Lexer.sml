structure Lexer: LEX =
struct

  (** =====================================================================
    * STATE MACHINE
    *
    * This bunch of mutually-recursive functions implements an efficient
    * state machine. Each is named `loop_<STATE_NAME>`. The arguments are
    * always
    *   `loop_XXX acc stream [args]`
    * where
    *   `acc` is a token accumulator,
    *   `stream` is the rest of the input, and
    *   `args` is a state-dependent state (haha)
    *)

  fun error acc msg =
    LexResult.Failure
      { partial = Seq.fromList (List.rev acc)
      , error = LexResult.Error.Other msg
      }

  fun success acc =
    LexResult.Success (Seq.fromList (List.rev acc))

  fun isReserved src =
    Option.isSome (Token.checkReserved src)

  fun tokens src =
    let
      (** Some helpers for making source slices and tokens. *)
      fun slice (i, j) = Source.subseq src (i, j-i)
      fun mk x (i, j) = Token.make (slice (i, j)) x
      fun mkr x (i, j) = Token.reserved (slice (i, j)) x
      fun mki (i, j) = Token.identifier (slice (i, j))
      fun mkq (i, j) = Token.qualifier (slice (i, j))

      fun get i = Source.nth src i

      (** This silliness lets you write almost-English like this:
        *   if is #"x" at            then ...
        *   if check isSymbolic at i then ...
        *)
      infix 5 at
      fun f at i = f i
      fun check f i = i < Source.length src andalso f (get i)
      fun is c = check (fn c' => c = c')

      fun next1 s =
        if s < Source.length src then
          SOME (Source.nth src s)
        else
          NONE

      fun next2 s =
        if s < Source.length src - 1 then
          SOME
            ( Source.nth src s
            , Source.nth src (s+1)
            )
        else
          NONE

      fun next3 s =
        if s < Source.length src - 2 then
          SOME
            ( Source.nth src s
            , Source.nth src (s+1)
            , Source.nth src (s+2)
            )
        else
          NONE

      fun next4 s =
        if s < Source.length src - 3 then
          SOME
            ( Source.nth src s
            , Source.nth src (s+1)
            , Source.nth src (s+2)
            , Source.nth src (s+3)
            )
        else
          NONE

      fun loop_topLevel acc s =
        case next1 s of
          SOME #"(" =>
            loop_afterOpenParen acc (s+1)
        | SOME #")" =>
            loop_topLevel (mkr Token.CloseParen (s, s+1) :: acc) (s+1)
        | SOME #"[" =>
            loop_topLevel (mkr Token.OpenSquareBracket (s, s+1) :: acc) (s+1)
        | SOME #"]" =>
            loop_topLevel (mkr Token.CloseSquareBracket (s, s+1) :: acc) (s+1)
        | SOME #"{" =>
            loop_topLevel (mkr Token.OpenCurlyBracket (s, s+1) :: acc) (s+1)
        | SOME #"}" =>
            loop_topLevel (mkr Token.CloseCurlyBracket (s, s+1) :: acc) (s+1)
        | SOME #"," =>
            loop_topLevel (mkr Token.Comma (s, s+1) :: acc) (s+1)
        | SOME #";" =>
            loop_topLevel (mkr Token.Semicolon (s, s+1) :: acc) (s+1)
        | SOME #"_" =>
            loop_topLevel (mkr Token.Underscore (s, s+1) :: acc) (s+1)
        | SOME #"\"" =>
            loop_inString acc (s+1) {stringStart = s}
        | SOME #"~" =>
            loop_afterTwiddle acc (s+1)
        | SOME #"'" =>
            loop_alphanumId acc (s+1)
              { idStart = s
              , startsPrime = true
              , isQualified = false
              }
        | SOME #"0" =>
            loop_afterZero acc (s+1)
        | SOME #"." =>
            loop_afterDot acc (s+1)
        | SOME c =>
            if LexUtils.isDecDigit c then
              loop_decIntegerConstant acc (s+1) {constStart = s}
            else if LexUtils.isSymbolic c then
              loop_symbolicId acc (s+1) {idStart = s, isQualified = false}
            else if LexUtils.isLetter c then
              loop_alphanumId acc (s+1)
                {idStart = s, startsPrime = false, isQualified = false}
            else
              loop_topLevel acc (s+1)
        | NONE =>
            (** DONE *)
            success acc


      and loop_afterDot acc s =
        if (is #"." at s) andalso (is #"." at s+1) then
          loop_topLevel
            (mkr Token.DotDotDot (s-1, s+2) :: acc)
            (s+2)
        else
          error acc "unexpected '.'"



      and loop_symbolicId acc s (args as {idStart, isQualified}) =
        if check LexUtils.isSymbolic at s then
          loop_symbolicId acc (s+1) args
        else
          let
            val srcHere = slice (idStart, s)
          in
            case Token.checkReserved srcHere of
              NONE =>
                loop_topLevel (Token.identifier srcHere :: acc) s
            | SOME r =>
                if isQualified then
                  error acc
                    ( "reserved word '"
                    ^ Source.toString srcHere
                    ^ "' prefaced by qualifiers"
                    )
                else
                  loop_topLevel (Token.reserved srcHere r :: acc) s
        end



      and loop_alphanumId acc s (args as {idStart, startsPrime, isQualified}) =
        if check LexUtils.isAlphaNumPrimeOrUnderscore at s then
          loop_alphanumId acc (s+1) args
        else if is #"." at s andalso startsPrime then
          error acc "structure identifiers cannot start with prime"
        else if is #"." at s then
          let
            val srcHere = slice (idStart, s)
          in
            case Token.checkReserved srcHere of
              SOME r =>
                error acc
                  ( "reserved word '"
                  ^ Source.toString srcHere
                  ^ "' cannot be used as qualifier"
                  )
            | NONE =>
                loop_continueLongIdentifier
                  (Token.qualifier srcHere :: acc)
                  (s+1)
          end
        else
          let
            val srcHere = slice (idStart, s)
          in
            case Token.checkReserved srcHere of
              NONE =>
                loop_topLevel (Token.identifier srcHere :: acc) s
            | SOME r =>
                if isQualified then
                  error acc
                    ( "reserved word '"
                    ^ Source.toString srcHere
                    ^ "' prefaced by qualifiers"
                    )
                else
                  loop_topLevel (Token.reserved srcHere r :: acc) s
          end



      and loop_continueLongIdentifier acc s =
        if check LexUtils.isSymbolic at s then
          loop_symbolicId acc (s+1) {idStart = s, isQualified = true}
        else if check LexUtils.isLetter at s then
          loop_alphanumId acc (s+1)
            { idStart = s
            , startsPrime = false
            , isQualified = true
            }
        else
          error acc "unexpected end of qualified identifier"



      (** After seeing a twiddle, we might be at the beginning of an integer
        * constant, or we might be at the beginning of a symbolic-id.
        *
        * Note that seeing "0" next is special, because of e.g. "0x" used to
        * indicate the beginning of hex format.
        *)
      and loop_afterTwiddle acc s =
        if is #"0" at s then
          loop_afterTwiddleThenZero acc (s+1)
        else if check LexUtils.isDecDigit at s then
          loop_decIntegerConstant acc (s+1) {constStart = s - 1}
        else if check LexUtils.isSymbolic at s then
          loop_symbolicId acc (s+1) {idStart = s - 1, isQualified = false}
        else
          loop_topLevel (mki (s - 1, s) :: acc) s



      (** Comes after "~0"
        * This might be the middle or end of an integer constant. We have
        * to first figure out if the integer constant is hex format.
        *)
      and loop_afterTwiddleThenZero acc s =
        if is #"x" at s andalso check LexUtils.isHexDigit at s+1 then
          loop_hexIntegerConstant acc (s+2) {constStart = s - 2}
        else if is #"." at s then
          loop_realConstantAfterDot acc (s+1) {constStart = s - 2}
        else if check LexUtils.isDecDigit at s then
          loop_decIntegerConstant acc (s+1) {constStart = s - 2}
        else
          loop_topLevel (mk Token.IntegerConstant (s - 2, s) :: acc) s



      (** After seeing "0", we're certainly at the beginning of some sort
        * of numeric constant. We need to figure out if this is an integer or
        * a word, and if it is hex or decimal format.
        *)
      and loop_afterZero acc s =
        if is #"x" at s andalso check LexUtils.isHexDigit at s+1 then
          loop_hexIntegerConstant acc (s+2) {constStart = s - 1}
        else if is #"w" at s then
          loop_afterZeroDubya acc (s+1)
        else if is #"." at s then
          loop_realConstantAfterDot acc (s+1) {constStart = s - 1}
        else if check LexUtils.isDecDigit at s then
          loop_decIntegerConstant acc (s+1) {constStart = s - 1}
        else
          loop_topLevel (mk Token.IntegerConstant (s-1, s) :: acc) s



      and loop_decIntegerConstant acc s (args as {constStart}) =
        if check LexUtils.isDecDigit at s then
          loop_decIntegerConstant acc (s+1) args
        else if is #"." at s then
          loop_realConstantAfterDot acc (s+1) args
        else
          loop_topLevel (mk Token.IntegerConstant (constStart, s) :: acc) s



      (** Immediately after the dot, we need to see at least one decimal digit *)
      and loop_realConstantAfterDot acc s (args as {constStart}) =
        if check LexUtils.isDecDigit at s then
          loop_realConstant acc (s+1) args
        else
          error acc ("unexpected end of real constant")


      (** Parsing the remainder of a real constant. This is already after the
        * dot, because the front of the real constant was already parsed as
        * an integer constant.
        *)
      and loop_realConstant acc s (args as {constStart}) =
        if check LexUtils.isDecDigit at s then
          loop_realConstant acc (s+1) args
        else if  is #"E" at s  orelse  is #"e" at s  then
          loop_realConstantAfterExponent acc (s+1) args
        else
          loop_topLevel
            (mk Token.RealConstant (constStart, s) :: acc)
            s



      and loop_realConstantAfterExponent acc s args =
        error acc "real constants with exponents not supported yet"



      and loop_hexIntegerConstant acc s (args as {constStart}) =
        if check LexUtils.isHexDigit at s then
          loop_hexIntegerConstant acc (s+1) args
        else
          loop_topLevel (mk Token.IntegerConstant (constStart, s) :: acc) s



      and loop_decWordConstant acc s (args as {constStart}) =
        if check LexUtils.isDecDigit at s then
          loop_decWordConstant acc (s+1) args
        else
          loop_topLevel (mk Token.WordConstant (constStart, s) :: acc) s



      and loop_hexWordConstant acc s (args as {constStart}) =
        if check LexUtils.isHexDigit at s then
          loop_hexWordConstant acc (s+1) args
        else
          loop_topLevel (mk Token.WordConstant (constStart, s) :: acc) s



      (** Comes after "0w"
        * It might be tempting to think that this is certainly a word constant,
        * but that's not necessarily true. Here's some possibilities:
        *   0w5       -- word constant 5
        *   0wx5      -- word constant 5, in hex format
        *   0w        -- integer constant 0 followed by alphanum-id "w"
        *   0wx       -- integer constant 0 followed by alphanum-id "wx"
        *)
      and loop_afterZeroDubya acc s =
        let
          (** In case the 0 ends up as an integer constant *)
          val zeroIntConstant =
            mk Token.IntegerConstant (s - 2, s - 1)
        in
          case next2 s of
            SOME (#"x", c) =>
              if LexUtils.isHexDigit c then
                loop_hexWordConstant acc (s+2) {constStart = s - 2}
              else
                loop_topLevel (zeroIntConstant :: acc) (s-1)
          | _ =>
          case next1 s of
            SOME c =>
              if LexUtils.isDecDigit c then
                loop_decWordConstant acc (s+1) {constStart = s - 2}
              else
                loop_topLevel (zeroIntConstant :: acc) (s-1)
          | NONE =>
              (** We're done, but need to parse the "0" as an integer constant,
                * and the "w" as an identifier. So back up to s-1 and continue.
                *)
              loop_alphanumId (zeroIntConstant :: acc) (s-1)
                { idStart = s-1
                , startsPrime = false
                , isQualified = false
                }
        end


      (** An open-paren could just be a normal paren, or it could be the
        * start of a comment.
        *)
      and loop_afterOpenParen acc s =
        if is #"*" at s then
          loop_inComment acc (s+1) {commentStart = s - 1, nesting = 1}
        else
          loop_topLevel (mkr Token.OpenParen (s - 1, s) :: acc) s



      and loop_inString acc s (args as {stringStart}) =
        case next1 s of
          SOME #"\\" (* " *) =>
            loop_inStringEscapeSequence acc (s+1) args
        | SOME #"\"" =>
            loop_topLevel
              (mk Token.StringConstant (stringStart, s+1) :: acc)
              (s+1)
        | SOME c =>
            if Char.isPrint c then
              loop_inString acc (s+1) args
            else
              error acc ("non-printable character at " ^ Int.toString (s))
        | NONE =>
            error acc ("unclosed string starting at " ^ Int.toString stringStart)



      (** Inside a string, and furthermore immediately inside a backslash *)
      and loop_inStringEscapeSequence acc s (args as {stringStart}) =
        case next1 s of
          SOME c =>
            if LexUtils.isValidSingleEscapeChar c then
              loop_inString acc (s+1) args
            else if LexUtils.isValidFormatEscapeChar c then
              loop_inStringFormatEscapeSequence acc (s+1) args
            else if c = #"^" then
              loop_inStringControlEscapeSequence acc (s+1) args
            else if c = #"u" then
              loop_inStringFourDigitEscapeSequence acc (s+1) args
            else if LexUtils.isDecDigit c then
              (** Note the `s` instead of `s+1`.
                * For consistency with the other functions, we put the index
                * immediately after the "preamble" (my term) of the escape
                * sequence.
                *)
              loop_inStringThreeDigitEscapeSequence acc s args
            else
              loop_inString acc s args
        | NONE =>
            error acc ("unclosed string starting at " ^ Int.toString stringStart)



      and loop_inStringThreeDigitEscapeSequence acc s args =
        case next3 s of
          SOME (c1, c2, c3) =>
            if List.all LexUtils.isDecDigit [c1, c2, c3] then
              loop_inString acc (s+3) args
            else
              error acc ("in string, expected escape sequence \\ddd but found"
                          ^ Source.toString (Source.subseq src (s-1, 4)))
        | NONE =>
            error acc ("incomplete three-digit escape sequence at " ^ Int.toString (s-1))



      and loop_inStringFourDigitEscapeSequence acc s args =
        case next4 s of
          SOME (c1, c2, c3, c4) =>
            if List.all LexUtils.isHexDigit [c1, c2, c3, c4] then
              loop_inString acc (s+4) args
            else
              error acc ("in string, expected escape sequence \\uxxxx but found"
                          ^ Source.toString (Source.subseq src (s-2, 6)))
        | NONE =>
            error acc ("incomplete four-digit escape sequence at " ^ Int.toString (s-2))



      (** Inside a string, and furthermore inside an escape sequence of
        * the form \^c
        *)
      and loop_inStringControlEscapeSequence acc s (args as {stringStart}) =
        case next1 s of
          SOME c =>
            if LexUtils.isValidControlEscapeChar c then
              loop_inStringEscapeSequence acc (s+1) args
            else
              error acc ("invalid control escape sequence at " ^ Int.toString s)
        | NONE =>
            error acc ("incomplete control escape sequence at " ^ Int.toString s)



      (** Inside a string, and furthermore inside an escape sequence of the
        * form \f...f\ where each f is a format character (space, newline, tab,
        * etc.)
        *)
      and loop_inStringFormatEscapeSequence acc s (args as {stringStart}) =
        case next1 s of
          SOME #"\\" (*"*) =>
            loop_inString acc (s+1) args
        | SOME c =>
            if LexUtils.isValidFormatEscapeChar c then
              loop_inStringFormatEscapeSequence acc (s+1) args
            else
              error acc ("invalid format escape sequence at " ^ Int.toString (s))
        | NONE =>
            error acc ("incomplete format escape sequence at " ^ Int.toString (s))


      (** Inside a comment that started at `commentStart`
        * `nesting` is always >= 0 and indicates how many open-comments we've seen.
        *)
      and loop_inComment acc s {commentStart, nesting} =
        if nesting = 0 then
          loop_topLevel (mk Token.Comment (commentStart, s) :: acc) s
        else

        case next2 s of
          SOME (#"(", #"*") =>
            loop_inComment acc (s+2) {commentStart=commentStart, nesting=nesting+1}
        | SOME (#"*", #")") =>
            loop_inComment acc (s+2) {commentStart=commentStart, nesting=nesting-1}
        | _ =>

        case next1 s of
          SOME _ =>
            loop_inComment acc (s+1) {commentStart=commentStart, nesting=nesting}
        | NONE =>
            error acc ("unclosed comment starting at " ^ Int.toString commentStart)

    in
      loop_topLevel [] 0
    end

end
