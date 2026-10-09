/// abstract contracts shared by the library implementation units
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.lib.core;

{
  *****************************************************************************

   Abstract Types and Interfaces Implemented by mormot.lib.* Units
   - Font Types: Specification, Metrics, Glyph Widths
   - Font Interfaces: Face, Provider, Enumerator, Shaper, Subsetter
   - Font Files: TrueType Collections
   - Font Services Registration

   The contracts of the font services implemented by mormot.lib.uniscribe
   (Windows), mormot.lib.freetype and mormot.lib.harfbuzz (POSIX), as needed
   by the cross-platform PDF engine, and the few font file helpers they share.

  *****************************************************************************
}

interface

{$I ..\mormot.defines.inc}

uses
  mormot.core.base;


{ ****************** Font Types: Specification, Metrics, Glyph Widths }

type
  /// opaque native handle of an IFontFace, for IFontShaper and IFontSubsetter
  // - a HFONT on Windows, a PFreeTypeFont with FreeType
  TFontHandle = type pointer;

  /// the requested font, as a Windows LOGFONTW gives it
  TFontRequest = record
    /// font family name, e.g. 'Calibri'
    FaceName: SynUnicode;
    /// character height in logical units - negative for the em height
    Height: integer;
    /// FW_NORMAL = 400, FW_BOLD = 700
    Weight: integer;
    /// 0 = upright, 1 = italic
    Italic: byte;
    /// 0 = ANSI_CHARSET
    CharSet: byte;
    /// FF_SWISS, FF_ROMAN... combined with the pitch
    PitchAndFamily: byte;
  end;

  /// basic metrics of a font, as a Windows TEXTMETRICW gives them
  TFontMetrics = record
    tmHeight: integer;
    tmAscent: integer;
    tmDescent: integer;
    tmInternalLeading: integer;
    tmExternalLeading: integer;
    tmAveCharWidth: integer;
    tmMaxCharWidth: integer;
    tmWeight: integer;
    tmOverhang: integer;
    tmFirstChar: WideChar;
    tmLastChar: WideChar;
    tmDefaultChar: WideChar;
    tmBreakChar: WideChar;
    tmItalic: byte;
    tmCharSet: byte;
    tmPitchAndFamily: byte;
  end;

  /// outline metrics of a font, as a Windows OUTLINETEXTMETRICW gives them
  TFontOutlineMetrics = record
    otmSize: cardinal;
    otmAscent: integer;
    otmDescent: integer;
    otmLineGap: integer;
    otmItalicAngle: integer;
    otmrcFontBox: record
      Left: integer;
      Top: integer;
      Right: integer;
      Bottom: integer;
    end;
    otmMacAscent: integer;
    otmMacDescent: integer;
    otmMacLineGap: cardinal;
    otmEMSquare: cardinal;
    otmCapEmHeight: integer;
    otmXHeight: integer;
    otmStrikeoutPosition: integer;
    otmStrikeoutSize: cardinal;
    otmUnderscorePosition: integer;
    otmUnderscoreSize: cardinal;
  end;

  /// the advance of one glyph in three parts, as a Windows ABC gives it
  // - the advance is abcA + abcB + abcC: an implementation scaling design
  // units has to scale the advance once and give abcB the remainder, so that
  // three roundings do not add up
  TFontCharAbc = record
    /// spacing before the glyph, may be negative
    abcA: integer;
    /// width of the glyph body
    abcB: cardinal;
    /// spacing after the glyph, may be negative
    abcC: integer;
  end;

  /// TFontCharAbc of consecutive characters
  TFontCharAbcArray = array of TFontCharAbc;

  /// how to draw one part of a shaped text
  // - fskPlain: draw the part unshaped - first, so that a run whose Kind was
  // never set falls back to the plain text
  // - fskShaped: Glyphs (and maybe Advances/Offsets/YOffsets) hold the result
  // - fskSkip: draw nothing for the part
  // - Outcome says why, e.g. fskPlain for fsoNotNeeded or fsoFailed
  TFontShapeKind = (
    fskPlain,
    fskShaped,
    fskSkip);

  /// why IFontShaper.Shape gave one part of the text its TFontShapeKind
  // - fsoUnknown: never set by a shaper - a run left zeroed; a caller draws
  // such a part unshaped, whatever its Kind
  // - fsoDone: the shaper did its work - including leaving out on purpose a
  // part which draws nothing
  // - fsoNotNeeded: the part needs no shaping
  // - fsoFailed: the shaper could not shape the part; Kind says what to draw
  // instead, e.g. fskSkip where the platform API used to drop it
  TFontShapeOutcome = (
    fsoUnknown,
    fsoDone,
    fsoNotNeeded,
    fsoFailed);

  /// one part of a shaped text, in visual order
  // - positions count UTF-16 code units of the whole source text
  // - horizontal layout: offsets move a glyph without moving the pen
  TFontShapedRun = record
    /// how to draw this part
    Kind: TFontShapeKind;
    /// why this part is drawn as Kind says
    Outcome: TFontShapeOutcome;
    /// first code unit of the part in the source text, 0-based
    TextStart: integer;
    /// number of code units of the part
    TextLen: integer;
    /// glyph indexes of the font, in visual order, as they are to be drawn
    // - a shaper may leave out glyphs which draw nothing, e.g. a zero-width
    // glyph which is no diacritic, keeping the other arrays aligned with Glyphs
    Glyphs: TWordDynArray;
    /// advance per glyph in 1/1000 em, positioned - empty when the advances
    // of the font apply
    Advances: TIntegerDynArray;
    /// horizontal offset per glyph in 1/1000 em, positive to the right
    // - empty when there is none
    Offsets: TIntegerDynArray;
    /// vertical offset per glyph in 1/1000 em, positive upwards, e.g. for a
    // mark placed by the font's GPOS table - empty when there is none
    YOffsets: TIntegerDynArray;
    /// source code unit of each glyph, in the whole text - empty when not known
    Clusters: TIntegerDynArray;
  end;

  /// the parts of a shaped text, in visual order
  TFontShapedRuns = array of TFontShapedRun;

  /// what IFontSubsetter.Subset has to keep
  TFontSubsetRequest = record
    /// code points whose cmap entries have to survive, e.g. the characters a
    // simple font reaches through the cmap
    Unicodes: TIntegerDynArray;
    /// glyph indexes which have to survive, e.g. glyphs addressed directly
    // or produced by shaping, which have no code point of their own
    Glyphs: TIntegerDynArray;
  end;


{ ****************** Font Interfaces: Face, Provider, Enumerator, Shaper, Subsetter }

const
  /// what IFontFace.GetFontData returns on failure (GDI_ERROR on Windows)
  FONT_DATA_ERROR = cardinal($ffffffff);

type
  /// one font face as a TFontRequest asked for, owning its native state
  // - from IFontProvider.CreateFace and released by reference counting, e.g.
  // shared by the WinAnsi and the Unicode font of a PDF document
  // - no selection into a device context: each method reads this face
  // - metrics and widths are those of a 1000 units per em face, as the PDF
  // engine asks with Height = -1000: GDI scales to the requested height, the
  // FreeType face always to 1000 units
  // - a face belongs to the thread that uses it: the GDI face keeps a device
  // context made by the thread which first measures it, valid while that
  // thread lives; FreeType shares one library between its faces
  IFontFace = interface
    ['{F0C800AA-DB24-4A34-93C0-8E22DF618DA2}']
    /// the native handle for IFontShaper and IFontSubsetter: a HFONT on
    // Windows, a PFreeTypeFont with FreeType - valid while the face lives
    function Handle: TFontHandle;
    /// the metrics of the face
    function GetTextMetrics(out Metrics: TFontMetrics): boolean;
    /// the outline metrics of the face
    function GetOutlineMetrics(out Metrics: TFontOutlineMetrics): boolean;
    /// the advances of the characters FirstChar..LastChar
    // - FirstChar and LastChar are WinAnsi (code page 1252) bytes, so that
    // 128..159 are punctuation, not C1 controls
    function GetCharAbcWidths(FirstChar, LastChar: cardinal;
      out Widths: TFontCharAbcArray): boolean;
    /// the advance of one glyph, by glyph index
    // - in the units of GetCharAbcWidths (abcA + abcB + abcC), e.g. for a
    // glyph a shaper produced which no character maps to
    function GetGlyphAdvance(Glyph: cardinal; out Advance: integer): boolean;
    /// read the raw bytes of a TrueType/OpenType table, as Windows GetFontData
    // - TableTag is the 4-byte tag read as a little-endian cardinal, e.g.
    // 'cmap', or 0 for the whole font: for a face of a .ttc, its table
    // directory with offsets into the collection, as GDI returns it
    // - returns the number of bytes, or FONT_DATA_ERROR
    function GetFontData(TableTag, Offset: cardinal; Buffer: pointer;
      BufferSize: cardinal): cardinal;
    /// the face as one standalone font file
    // - a face of a .ttc collection is extracted from it: a collection is
    // no font program, e.g. for a PDF /FontFile2
    // - returns false if the face cannot be found in or extracted from its
    // collection
    function GetFaceFile(out Face: RawByteString): boolean;
  end;

  /// create font faces
  IFontProvider = interface
    ['{EDA8601C-380D-43C7-8B9A-5DC50516C103}']
    /// the face the system resolves Request to, nil on failure
    function CreateFace(const Request: TFontRequest): IFontFace;
  end;

  /// list the fonts available on the system
  IFontEnumerator = interface
    ['{43E765AA-942B-4058-A843-7B7FED1324B6}']
    /// add the UTF-8 family names of the TrueType fonts to List
    procedure EnumTrueTypeFonts(var List: TRawUtf8DynArray);
  end;

  /// shape Unicode text with the OpenType rules of a font
  // - for complex scripts and right-to-left text: Arabic, Hebrew, Indic...
  IFontShaper = interface
    ['{EFE07440-0B89-41ED-8E99-07106AB07ABF}']
    /// shape Len characters of Text with Font
    // - RightToLeft forces the direction; false lets the script decide
    // - returns false when the whole text should be drawn unshaped, e.g.
    // because no part of it needs shaping or the shaper failed
    // - otherwise the runs cover every code unit of Text once, in visual
    // order, a part left out included (Kind = fskSkip); every run has its
    // Kind and Outcome set
    function Shape(Text: PWideChar; Len: integer; Font: TFontHandle;
      RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
  end;

  /// make a subset of a TrueType/OpenType font
  IFontSubsetter = interface
    ['{0879A056-B4AE-44DD-8630-56F9A362E5D0}']
    /// return the subset of Face which keeps what Request lists
    // - Face holds the font bytes, Font the IFontFace.Handle they were read
    // from
    // - glyph indexes are kept, so data built against Face stays valid
    // - returns false if the font cannot be subset: the caller keeps Face
    function Subset(const Face: RawByteString; const Request: TFontSubsetRequest;
      Font: TFontHandle; out Output: RawByteString): boolean;
    /// true if Subset keeps the glyphs of a symbol font, which reaches them
    // through a (3,0) cmap at U+F0xx rather than through Request.Unicodes
    // - a caller embeds a symbol font whole when this is false
    function SupportsSymbolic: boolean;
  end;


{ ****************** Font Files: TrueType Collections }

/// extract one face of a TrueType Collection as a standalone sfnt font
// - a 'ttcf' container is not a valid /FontFile2 stream: it must be turned into
//   a single font, which both backends do with this function
//   (IFontProvider.GetFaceFile)
// - returns '' when ATtc is not a collection, i.e. already a usable sfnt
function ExtractSfntFromTtc(const ATtc: RawByteString;
  AFaceIndex: integer): RawByteString;

/// the index of a face in a .ttc collection, from the bytes
// - Face is the face as IFontFace.GetFontData(0, ...) returns it: its table
// directory is the one at the offset of its index in the collection header
// - returns -1 if no face, or more than one, matches
function TtcFaceIndex(const Ttc, Face: RawByteString): integer;


{ ****************** Font Services Registration }

var
  /// the registered font provider, nil until an implementation registers
  FontProvider: IFontProvider;
  /// the registered font enumerator
  FontEnumerator: IFontEnumerator;
  /// the registered text shaper, nil when no shaping library is available
  FontShaper: IFontShaper;
  /// the registered font subsetter, nil when none is available
  FontSubsetter: IFontSubsetter;

/// register the font services of an implementation unit
// - a nil parameter leaves the current registration unchanged
procedure RegisterFontPlatform(const Provider: IFontProvider;
  const Enumerator: IFontEnumerator);

/// true when a provider and an enumerator are registered
function FontPlatformRegistered: boolean;


implementation


{ ****************** Font Files: TrueType Collections }

function BigEndian32(P: PAnsiChar): cardinal;
begin
  result := (cardinal(ord(P[0])) shl 24) or (cardinal(ord(P[1])) shl 16) or
            (cardinal(ord(P[2])) shl 8) or cardinal(ord(P[3]));
end;

function TtcFaceIndex(const Ttc, Face: RawByteString): integer;
var
  n, i, ofs, dirlen: cardinal;
begin
  result := -1;
  if (length(Face) < 12) or
     (length(Ttc) < 16) or
     (BigEndian32(pointer(Ttc)) <> $74746366) then // 'ttcf'
    exit;
  dirlen := 12 + 16 * ((cardinal(ord(Face[5])) shl 8) or cardinal(ord(Face[6])));
  if cardinal(length(Face)) < dirlen then
    exit;
  n := BigEndian32(@Ttc[9]);
  if (n = 0) or
     (n > (cardinal(length(Ttc)) - 12) div 4) then // no overflow of n * 4
    exit;
  for i := 0 to n - 1 do
  begin
    ofs := BigEndian32(@Ttc[13 + i * 4]);
    if (ofs <= cardinal(length(Ttc))) and
       (dirlen <= cardinal(length(Ttc)) - ofs) and
       CompareMem(@Ttc[ofs + 1], pointer(Face), dirlen) then
      if result >= 0 then
      begin
        result := -1; // ambiguous: no reliable index
        exit;
      end
      else
        result := i;
  end;
end;

const
  TTCF_MAGIC = $66637474; // 'ttcf' read as a little-endian cardinal

function ExtractSfntFromTtc(const ATtc: RawByteString;
  AFaceIndex: integer): RawByteString;
var
  base, dir, src, dst: PAnsiChar;
  numFonts, numTables, i, faceOfs, ofs, len, total, hd, size: PtrUInt;
  sum: cardinal;
begin
  // every bound is checked as "value > size - offset": a sum could wrap
  // around where PtrUInt has 32 bits
  result := '';
  base := pointer(ATtc);
  size := length(ATtc);
  if (size < 16) or
     (PCardinal(base)^ <> TTCF_MAGIC) then
    exit; // not a collection: the caller may embed the data as it is
  numFonts := bswap32(PCardinal(base + 8)^);
  if (AFaceIndex < 0) or
     (PtrUInt(AFaceIndex) >= numFonts) or
     (numFonts > (size - 12) shr 2) then
    exit;
  faceOfs := bswap32(PCardinal(base + 12 + PtrUInt(AFaceIndex) * 4)^);
  if faceOfs > size - 12 then
    exit;
  numTables := bswap16(PWord(base + faceOfs + 4)^);
  if (numTables = 0) or
     (numTables * 16 > size - faceOfs - 12) then
    exit;
  // measure the standalone font: offset table, directory, then 4-byte aligned
  // table data - the table bytes are copied verbatim, so their per-table
  // checksums stay valid
  total := 12 + numTables * 16;
  dir := base + faceOfs + 12;
  for i := 0 to numTables - 1 do
  begin
    ofs := bswap32(PCardinal(dir + i * 16 + 8)^);
    len := bswap32(PCardinal(dir + i * 16 + 12)^);
    if (ofs > size) or
       (len > size - ofs) or
       (((len + 3) and not PtrUInt(3)) > PtrUInt(MaxInt) - total) then
      exit; // truncated or malformed collection
    inc(total, (len + 3) and not PtrUInt(3));
  end;
  FastSetRawByteString(result, nil, total);
  dst := pointer(result);
  MoveFast(base[faceOfs], dst^, 12 + numTables * 16); // header + directory
  src := dst + 12 + numTables * 16;
  hd := 0;
  for i := 0 to numTables - 1 do
  begin
    ofs := bswap32(PCardinal(dir + i * 16 + 8)^);
    len := bswap32(PCardinal(dir + i * 16 + 12)^);
    if (PCardinal(dir + i * 16)^ = $64616568) and // 'head' little-endian
       (len >= 12) then // checkSumAdjustment at offset 8
      hd := PtrUInt(src - dst);
    PCardinal(dst + 12 + i * 16 + 8)^ := bswap32(cardinal(src - dst));
    MoveFast(base[ofs], src^, len);
    FillCharFast(src[len], ((len + 3) and not PtrUInt(3)) - len, 0);
    inc(src, (len + 3) and not PtrUInt(3));
  end;
  if hd <> 0 then
  begin
    // head.checkSumAdjustment covers the whole file, so it must be recomputed
    PCardinal(dst + hd + 8)^ := 0;
    sum := 0;
    for i := 0 to (total shr 2) - 1 do
      inc(sum, bswap32(PCardinalArray(dst)^[i]));
    PCardinal(dst + hd + 8)^ := bswap32(cardinal($B1B0AFBA) - sum);
  end;
end;


{ ****************** Font Services Registration }

procedure RegisterFontPlatform(const Provider: IFontProvider;
  const Enumerator: IFontEnumerator);
begin
  if Provider <> nil then
    FontProvider := Provider;
  if Enumerator <> nil then
    FontEnumerator := Enumerator;
end;

function FontPlatformRegistered: boolean;
begin
  result := (FontProvider <> nil) and
            (FontEnumerator <> nil);
end;


end.
