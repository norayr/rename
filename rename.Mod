MODULE rename;

IMPORT Oberon, Texts, Files, Strings, Out;

CONST
  MaxName = 256;
  MaxArgs = 128;

TYPE
  String = ARRAY MaxName OF CHAR;
  Args = ARRAY MaxArgs OF String;

VAR
  argc: INTEGER;
  argv: Args;
  dry, verbose, all, last, glob: BOOLEAN;


PROCEDURE Usage;
BEGIN
  Out.String("usage: rename [-n] [-v] [-a|-l] FROM TO FILE..."); Out.Ln;
  Out.String("       rename -g [-n] [-v] FROMPAT TOPAT FILE..."); Out.Ln;
  Out.Ln;
  Out.String("  default: replace first occurrence of FROM with TO"); Out.Ln;
  Out.String("  -a      replace all occurrences"); Out.Ln;
  Out.String("  -l      replace last occurrence"); Out.Ln;
  Out.String("  -g      glob-template mode, e.g. '*.txt' '*.text'"); Out.Ln;
  Out.String("  -n      dry run"); Out.Ln;
  Out.String("  -v      verbose"); Out.Ln
END Usage;


PROCEDURE Len(s: ARRAY OF CHAR): INTEGER;
BEGIN
  RETURN Strings.Length(s)
END Len;


PROCEDURE Clear(VAR s: ARRAY OF CHAR);
BEGIN
  s[0] := 0X
END Clear;


PROCEDURE AppendChar(VAR s: ARRAY OF CHAR; ch: CHAR);
VAR n: INTEGER;
BEGIN
  n := Len(s);
  IF n + 1 < LEN(s) THEN
    s[n] := ch;
    s[n+1] := 0X
  END
END AppendChar;


PROCEDURE AppendString(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (src[i] # 0X) & (Len(dst) + 1 < LEN(dst)) DO
    AppendChar(dst, src[i]);
    INC(i)
  END
END AppendString;


PROCEDURE AppendSlice(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR; from, till: INTEGER);
VAR i: INTEGER;
BEGIN
  i := from;
  WHILE (i < till) & (src[i] # 0X) & (Len(dst) + 1 < LEN(dst)) DO
    AppendChar(dst, src[i]);
    INC(i)
  END
END AppendSlice;


PROCEDURE Equal(a, b: ARRAY OF CHAR): BOOLEAN;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (a[i] # 0X) & (b[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
  RETURN a[i] = b[i]
END Equal;


PROCEDURE IsOpt(s: ARRAY OF CHAR; ch: CHAR): BOOLEAN;
BEGIN
  RETURN (s[0] = "-") & (s[1] = ch) & (s[2] = 0X)
END IsOpt;


PROCEDURE ReadArgs;
VAR
  R: Texts.Reader;
  ch: CHAR;
  inQuote: BOOLEAN;
  q: CHAR;

  PROCEDURE SkipSpaces;
  BEGIN
    WHILE ~R.eot & ((ch = " ") OR (ch = 09X) OR (ch = 0DX) OR (ch = 0AX)) DO
      Texts.Read(R, ch)
    END
  END SkipSpaces;

  PROCEDURE ReadOne(VAR s: ARRAY OF CHAR);
  VAR i: INTEGER;
  BEGIN
    Clear(s);
    i := 0;
    inQuote := FALSE;
    q := 0X;

    LOOP
      IF R.eot THEN EXIT END;

      IF inQuote THEN
        IF ch = q THEN
          inQuote := FALSE
        ELSE
          IF i + 1 < LEN(s) THEN s[i] := ch; INC(i) END
        END
      ELSE
        IF (ch = " ") OR (ch = 09X) OR (ch = 0DX) OR (ch = 0AX) THEN
          EXIT
        ELSIF (ch = 22X) OR (ch = 27X) THEN
          inQuote := TRUE;
          q := ch
        ELSE
          IF i + 1 < LEN(s) THEN s[i] := ch; INC(i) END
        END
      END;

      Texts.Read(R, ch)
    END;

    s[i] := 0X
  END ReadOne;

BEGIN
  argc := 0;
  Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
  Texts.Read(R, ch);

  WHILE ~R.eot & (argc < MaxArgs) DO
    SkipSpaces;
    IF ~R.eot THEN
      ReadOne(argv[argc]);
      INC(argc)
    END
  END
END ReadArgs;


PROCEDURE FindLast(pat, s: ARRAY OF CHAR): INTEGER;
VAR p, q: INTEGER;
BEGIN
  p := -1;
  q := Strings.Pos(pat, s, 0);
  WHILE q >= 0 DO
    p := q;
    q := Strings.Pos(pat, s, q + 1)
  END;
  RETURN p
END FindLast;


PROCEDURE ReplaceFirst(name, from, to: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
VAR p, lf: INTEGER;
BEGIN
  p := Strings.Pos(from, name, 0);
  IF p < 0 THEN RETURN FALSE END;

  lf := Len(from);
  Clear(out);
  AppendSlice(out, name, 0, p);
  AppendString(out, to);
  AppendSlice(out, name, p + lf, Len(name));
  RETURN TRUE
END ReplaceFirst;


PROCEDURE ReplaceLast(name, from, to: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
VAR p, lf: INTEGER;
BEGIN
  p := FindLast(from, name);
  IF p < 0 THEN RETURN FALSE END;

  lf := Len(from);
  Clear(out);
  AppendSlice(out, name, 0, p);
  AppendString(out, to);
  AppendSlice(out, name, p + lf, Len(name));
  RETURN TRUE
END ReplaceLast;


PROCEDURE ReplaceAll(name, from, to: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
VAR p, start, lf: INTEGER; changed: BOOLEAN;
BEGIN
  lf := Len(from);
  IF lf = 0 THEN RETURN FALSE END;

  Clear(out);
  start := 0;
  changed := FALSE;
  p := Strings.Pos(from, name, start);

  WHILE p >= 0 DO
    AppendSlice(out, name, start, p);
    AppendString(out, to);
    start := p + lf;
    changed := TRUE;
    p := Strings.Pos(from, name, start)
  END;

  AppendSlice(out, name, start, Len(name));
  RETURN changed
END ReplaceAll;


PROCEDURE StarPos(s: ARRAY OF CHAR): INTEGER;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    IF s[i] = "*" THEN RETURN i END;
    INC(i)
  END;
  RETURN -1
END StarPos;


PROCEDURE GlobReplace(name, fromPat, toPat: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
VAR
  sp, tp: INTEGER;
  preLen, sufLen, nameLen: INTEGER;
BEGIN
  sp := StarPos(fromPat);
  tp := StarPos(toPat);

  IF sp < 0 THEN
    (* no star: exact whole-name match *)
    IF ~Equal(name, fromPat) THEN RETURN FALSE END;
    COPY(toPat, out);
    RETURN TRUE
  END;

  nameLen := Len(name);
  preLen := sp;
  sufLen := Len(fromPat) - sp - 1;

  IF nameLen < preLen + sufLen THEN RETURN FALSE END;

  (* prefix must match *)
  IF preLen > 0 THEN
    IF Strings.Pos(fromPat, name, 0) # 0 THEN
      RETURN FALSE
    END
  END;

  (* suffix must match *)
  IF sufLen > 0 THEN
    IF Strings.Pos(fromPat, name, 0) = 0 THEN
      (* do nothing; exact prefix test above is not enough for suffix *)
    END
  END;

  (* manual suffix check *)
  WHILE sufLen > 0 DO
    IF name[nameLen - sufLen] # fromPat[Len(fromPat) - sufLen] THEN
      RETURN FALSE
    END;
    DEC(sufLen)
  END;

  Clear(out);

  IF tp < 0 THEN
    AppendString(out, toPat)
  ELSE
    AppendSlice(out, toPat, 0, tp);
    AppendSlice(out, name, preLen, nameLen - (Len(fromPat) - sp - 1));
    AppendSlice(out, toPat, tp + 1, Len(toPat))
  END;

  RETURN TRUE
END GlobReplace;


PROCEDURE Exists(name: ARRAY OF CHAR): BOOLEAN;
VAR f: Files.File;
BEGIN
  f := Files.Old(name);
  RETURN f # NIL
END Exists;


PROCEDURE DoRename(old, new: ARRAY OF CHAR);
VAR res: INTEGER;
BEGIN
  IF Equal(old, new) THEN
    IF verbose THEN
      Out.String(old); Out.String(": unchanged"); Out.Ln
    END;
    RETURN
  END;

  IF Exists(new) THEN
    Out.String(old); Out.String(": target exists: "); Out.String(new); Out.Ln;
    RETURN
  END;

  IF dry OR verbose THEN
    Out.String(old); Out.String(" -> "); Out.String(new); Out.Ln
  END;

  IF ~dry THEN
    Files.Rename(old, new, res);
    IF res # 0 THEN
      Out.String(old); Out.String(": rename failed, res=");
      Out.Int(res, 1); Out.Ln
    END
  END
END DoRename;


PROCEDURE ParseOptions(VAR first: INTEGER);
BEGIN
  dry := FALSE; verbose := FALSE; all := FALSE; last := FALSE; glob := FALSE;
  first := 0;

  WHILE (first < argc) & (argv[first][0] = "-") DO
    IF IsOpt(argv[first], "n") THEN dry := TRUE
    ELSIF IsOpt(argv[first], "v") THEN verbose := TRUE
    ELSIF IsOpt(argv[first], "a") THEN all := TRUE
    ELSIF IsOpt(argv[first], "l") THEN last := TRUE
    ELSIF IsOpt(argv[first], "g") THEN glob := TRUE
    ELSE
      Usage;
      HALT(1)
    END;
    INC(first)
  END;

  IF all & last THEN
    Out.String("rename: -a and -l cannot be used together"); Out.Ln;
    HALT(1)
  END
END ParseOptions;


PROCEDURE Main;
VAR
  first, i: INTEGER;
  from, to, old, new: String;
  changed: BOOLEAN;
BEGIN
  ReadArgs;
  ParseOptions(first);

  IF argc - first < 3 THEN
    Usage;
    HALT(1)
  END;

  COPY(argv[first], from);
  COPY(argv[first + 1], to);

  i := first + 2;
  WHILE i < argc DO
    COPY(argv[i], old);

    IF glob THEN
      changed := GlobReplace(old, from, to, new)
    ELSIF all THEN
      changed := ReplaceAll(old, from, to, new)
    ELSIF last THEN
      changed := ReplaceLast(old, from, to, new)
    ELSE
      changed := ReplaceFirst(old, from, to, new)
    END;

    IF changed THEN
      DoRename(old, new)
    ELSIF verbose THEN
      Out.String(old); Out.String(": no match"); Out.Ln
    END;

    INC(i)
  END
END Main;


BEGIN
  Main
END rename.

