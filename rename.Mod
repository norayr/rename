MODULE rename;

IMPORT Oberon, Texts, Files, Strings, Out, Platform;

CONST
  MaxName = 256;
  MaxArgs = 128;

TYPE
  String = ARRAY MaxName OF CHAR;
  Args = ARRAY MaxArgs OF String;

VAR
  argc: INTEGER;
  argv: Args;
  dry, verbose, all, last, glob, overwrite: BOOLEAN;


PROCEDURE Usage;
BEGIN
  Out.String("usage: rename [-n] [-v] [-o|-f] [-a|-l] FROM TO FILE..."); Out.Ln;
  Out.String("       rename -g [-n] [-v] [-o|-f] FROMPAT TOPAT FILE..."); Out.Ln;
  Out.Ln;
  Out.String("  default: replace first occurrence of FROM with TO"); Out.Ln;
  Out.String("  -a      replace all occurrences"); Out.Ln;
  Out.String("  -l      replace last occurrence"); Out.Ln;
  Out.String("  -g      glob-template mode, e.g. '*.txt' '*.text'"); Out.Ln;
  Out.String("  -o      no overwrite (default)"); Out.Ln;
  Out.String("  -f      force overwrite existing target"); Out.Ln;
  Out.String("  -n      dry run"); Out.Ln;
  Out.String("  -v      verbose"); Out.Ln
END Usage;


PROCEDURE Equal(a, b: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN (Strings.Length(a) = Strings.Length(b)) & (Strings.Pos(a, b, 0) = 0)
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
    s[0] := 0X;
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
VAR
  p, lf, ln: INTEGER;
  tmp: String;
BEGIN
  p := Strings.Pos(from, name, 0);
  IF p < 0 THEN RETURN FALSE END;

  lf := Strings.Length(from);
  ln := Strings.Length(name);

  out[0] := 0X;

  Strings.Extract(name, 0, p, tmp);
  Strings.Append(tmp, out);

  Strings.Append(to, out);

  Strings.Extract(name, p + lf, ln - p - lf, tmp);
  Strings.Append(tmp, out);

  RETURN TRUE
END ReplaceFirst;

PROCEDURE ReplaceLast(name, from, to: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
VAR
  p, lf, ln: INTEGER;
  tmp: String;
BEGIN
  lf := Strings.Length(from);
  IF lf = 0 THEN RETURN FALSE END;

  p := FindLast(from, name);
  IF p < 0 THEN RETURN FALSE END;

  ln := Strings.Length(name);
  out[0] := 0X;

  Strings.Extract(name, 0, p, tmp);
  Strings.Append(tmp, out);

  Strings.Append(to, out);

  Strings.Extract(name, p + lf, ln - p - lf, tmp);
  Strings.Append(tmp, out);

  RETURN TRUE
END ReplaceLast;

PROCEDURE ReplaceAll(name, from, to: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
VAR
  p, start, lf, ln: INTEGER;
  tmp: String;
  changed: BOOLEAN;
BEGIN
  lf := Strings.Length(from);
  IF lf = 0 THEN RETURN FALSE END;

  ln := Strings.Length(name);
  out[0] := 0X;
  start := 0;
  changed := FALSE;

  p := Strings.Pos(from, name, start);
  WHILE p >= 0 DO
    Strings.Extract(name, start, p - start, tmp);
    Strings.Append(tmp, out);

    Strings.Append(to, out);

    start := p + lf;
    changed := TRUE;

    p := Strings.Pos(from, name, start)
  END;

  Strings.Extract(name, start, ln - start, tmp);
  Strings.Append(tmp, out);

  RETURN changed
END ReplaceAll;

PROCEDURE GlobReplace(name, fromPat, toPat: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
VAR
  sp, tp: INTEGER;
  fromLen, toLen, nameLen: INTEGER;
  preLen, sufLen, capLen: INTEGER;
  i: INTEGER;
  ok: BOOLEAN;
  tmp: String;
BEGIN
  sp := Strings.Pos("*", fromPat, 0);
  tp := Strings.Pos("*", toPat, 0);

  fromLen := Strings.Length(fromPat);
  toLen := Strings.Length(toPat);
  nameLen := Strings.Length(name);

  out[0] := 0X;

  IF sp < 0 THEN
    (* No star in source pattern: require exact whole-name match. *)
    IF ~Equal(name, fromPat) THEN RETURN FALSE END;
    Strings.Append(toPat, out);
    RETURN TRUE
  END;

  preLen := sp;
  sufLen := fromLen - sp - 1;

  IF nameLen < preLen + sufLen THEN RETURN FALSE END;

  (* Check prefix before *. *)
  ok := TRUE;
  i := 0;
  WHILE ok & (i < preLen) DO
    IF name[i] # fromPat[i] THEN ok := FALSE END;
    INC(i)
  END;
  IF ~ok THEN RETURN FALSE END;

  (* Check suffix after *. *)
  i := 0;
  WHILE ok & (i < sufLen) DO
    IF name[nameLen - sufLen + i] # fromPat[sp + 1 + i] THEN
      ok := FALSE
    END;
    INC(i)
  END;
  IF ~ok THEN RETURN FALSE END;

  capLen := nameLen - preLen - sufLen;

  IF tp < 0 THEN
    (* Target has no star: replace whole matched name with fixed target. *)
    Strings.Append(toPat, out)
  ELSE
    (* Target prefix before *. *)
    Strings.Extract(toPat, 0, tp, tmp);
    Strings.Append(tmp, out);

    (* Captured middle from source name. *)
    Strings.Extract(name, preLen, capLen, tmp);
    Strings.Append(tmp, out);

    (* Target suffix after *. *)
    Strings.Extract(toPat, tp + 1, toLen - tp - 1, tmp);
    Strings.Append(tmp, out)
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
    IF ~overwrite THEN
      Out.String(old); Out.String(": target exists: "); Out.String(new); Out.Ln;
      RETURN
    END
  END;

  IF dry OR verbose THEN
    Out.String(old); Out.String(" -> "); Out.String(new); Out.Ln
  END;

  IF ~dry THEN
    IF overwrite & Exists(new) THEN
      Files.Delete(new, res);
      IF res # 0 THEN
        Out.String(old); Out.String(": cannot remove existing target: ");
        Out.String(new); Out.String(", res="); Out.Int(res, 1); Out.Ln;
        RETURN
      END
    END;

    Files.Rename(old, new, res);
    IF res # 0 THEN
      Out.String(old); Out.String(": rename failed, res=");
      Out.Int(res, 1); Out.Ln
    END
  END
END DoRename;

PROCEDURE ParseOptions(VAR first: INTEGER);
BEGIN
  dry := FALSE; verbose := FALSE; all := FALSE; last := FALSE;
  glob := FALSE; overwrite := FALSE;
  first := 0;

  WHILE (first < argc) & (argv[first][0] = "-") DO
    IF IsOpt(argv[first], "n") THEN dry := TRUE
    ELSIF IsOpt(argv[first], "v") THEN verbose := TRUE
    ELSIF IsOpt(argv[first], "a") THEN all := TRUE
    ELSIF IsOpt(argv[first], "l") THEN last := TRUE
    ELSIF IsOpt(argv[first], "g") THEN glob := TRUE
    ELSIF IsOpt(argv[first], "o") THEN overwrite := FALSE
    ELSIF IsOpt(argv[first], "f") THEN overwrite := TRUE
    ELSE
      Usage;
      Platform.Exit(1)
    END;
    INC(first)
  END;

  IF all & last THEN
    Out.String("rename: -a and -l cannot be used together"); Out.Ln;
    Platform.Exit(1)
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
    Platform.Exit(1)
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

