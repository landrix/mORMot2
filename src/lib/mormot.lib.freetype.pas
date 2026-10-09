/// low-level access to the FreeType2 library, and its font services
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.lib.freetype;

{
  *****************************************************************************

   FreeType2 Font Services for POSIX
   - FreeType2 Minimal API Bindings (dynamic loading)
   - Font Files Discovery: /usr/share/fonts, ~/.fonts, macOS /Library/Fonts
   - Font Collections and Face Sizing
   - IFontProvider, IFontEnumerator and IFontDC Implementation

   The initialization section registers the three services of mormot.lib.core
   when libfreetype.so.6 / libfreetype.6.dylib loads.

  *****************************************************************************
}

interface

{$I ..\mormot.defines.inc}

{$ifdef OSWINDOWS}

// do-nothing-unit on Windows system

implementation

{$else}

uses
  SysUtils,
  Classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.lib.core;


{ ****************** FreeType2 Minimal API Bindings }

type
  FT_Library  = pointer;
  FT_Face     = pointer;
  FT_Error    = integer;
  // FT_Long/FT_ULong follow the C 'long' type:
  //   - 64-bit on LP64 platforms (Linux x86_64, macOS/ARM64, macOS/x86_64)
  //   - 32-bit on LLP64 platforms (Windows 64-bit)
  {$ifdef CPU64}
  FT_Long    = Int64;
  FT_ULong   = QWord;
  FT_Pos     = Int64;     // typedef FT_Long FT_Pos
  FT_Fixed   = Int64;     // typedef FT_Long FT_Fixed
  FT_F26Dot6 = Int64;     // typedef FT_Long FT_F26Dot6
  {$else}
  FT_Long    = longint;
  FT_ULong   = cardinal;
  FT_Pos     = longint;
  FT_Fixed   = longint;
  FT_F26Dot6 = longint;
  {$endif CPU64}
  FT_Int      = integer;  // always 32-bit (C 'int')
  FT_UInt     = cardinal; // always 32-bit (C 'unsigned int')

  FT_BBox = record
    xMin, yMin, xMax, yMax: FT_Pos;
  end;

  // FT_FaceRec - we only access the fields we need via typed pointer
  PFT_FaceRec = ^FT_FaceRec;
  FT_FaceRec = record
    num_faces:        FT_Long;
    face_index:       FT_Long;
    face_flags:       FT_Long;
    style_flags:      FT_Long;
    num_glyphs:       FT_Long;
    family_name:      PAnsiChar;
    style_name:       PAnsiChar;
    num_fixed_sizes:  FT_Int;
    available_sizes:  pointer;
    num_charmaps:     FT_Int;
    charmaps:         pointer;
    generic_data:     pointer;
    generic_finalizer: pointer;
    bbox:             FT_BBox;
    units_per_EM:     Word;        // FT_UShort = 2 bytes
    ascender:         SmallInt;    // FT_Short  = 2 bytes
    descender:        SmallInt;    // negative value
    height:           SmallInt;
    max_advance_width:  SmallInt;
    max_advance_height: SmallInt;
    underline_position:  SmallInt;
    underline_thickness: SmallInt;
    glyph:           pointer;
    size:            pointer;
    charmap:         pointer;
  end;

  // FT_GlyphSlotRec - we only need metrics
  PFT_GlyphMetrics = ^FT_GlyphMetrics;
  FT_GlyphMetrics = record
    width:         FT_Pos;
    height:        FT_Pos;
    horiBearingX:  FT_Pos;
    horiBearingY:  FT_Pos;
    horiAdvance:   FT_Pos;
    vertBearingX:  FT_Pos;
    vertBearingY:  FT_Pos;
    vertAdvance:   FT_Pos;
  end;

  PFT_GlyphSlotRec = ^FT_GlyphSlotRec;
  FT_GlyphSlotRec = record
    library_:      FT_Library;
    face:          FT_Face;
    next:          pointer;
    reserved:      FT_UInt;
    generic_data:  pointer;
    generic_finalizer: pointer;
    metrics:       FT_GlyphMetrics;
    // ... more fields we don't need
  end;

// FreeType2 function pointer types
type
  TFT_Init_FreeType     = function(var alibrary: FT_Library): FT_Error; cdecl;
  TFT_Done_FreeType     = function(alibrary: FT_Library): FT_Error; cdecl;
  TFT_New_Face          = function(alibrary: FT_Library; filepathname: PAnsiChar;
                            face_index: FT_Long; var aface: FT_Face): FT_Error; cdecl;
  TFT_Done_Face         = function(face: FT_Face): FT_Error; cdecl;
  TFT_Set_Char_Size     = function(face: FT_Face; char_width, char_height: FT_F26Dot6;
                            horz_resolution, vert_resolution: FT_UInt): FT_Error; cdecl;
  TFT_Load_Char         = function(face: FT_Face; char_code: FT_ULong;
                            load_flags: FT_Int): FT_Error; cdecl;
  TFT_Load_Sfnt_Table   = function(face: FT_Face; tag: FT_ULong; offset: FT_Long;
                            buffer: pointer; var length: FT_ULong): FT_Error; cdecl;

const
  FT_LOAD_DEFAULT         = 0;
  FT_LOAD_NO_SCALE        = 1;  // = 1 shl 0; returns raw design units, no 26.6 encoding
  FT_FACE_FLAG_FIXED_WIDTH = 1 shl 2;

  /// standard DPI used when no real screen DPI is available
  FREETYPE_SCREEN_DPI = 96;

type
  /// the loaded FreeType2 library and its function pointers
  // - the function fields are resolved in their declaration order
  TFreeTypeLib = class(TSynLibrary)
  protected
    fLoaded: boolean;
  public
    Init:             TFT_Init_FreeType;
    Done:             TFT_Done_FreeType;
    NewFace:          TFT_New_Face;
    DoneFace:         TFT_Done_Face;
    SetCharSize:      TFT_Set_Char_Size;
    LoadChar:         TFT_Load_Char;
    LoadSfntTable:    TFT_Load_Sfnt_Table;
    /// the FT_Library instance of FT_Init_FreeType
    FTLibrary:        FT_Library;
    /// true once the library is loaded and initialized - false on nil
    function Loaded: boolean;
      {$ifdef HASINLINE} inline; {$endif}
  end;

var
  /// global FreeType2 library instance, nil until LoadFreeType succeeds
  FreeType: TFreeTypeLib;

/// load the FreeType2 shared library; returns false if not found
function LoadFreeType: boolean;


{ ****************** Font Files Discovery }

type
  /// maps a font family name (UTF-8) to the best matching .ttf/.otf file path
  TFontFileMap = record
    FamilyName: RawUtf8;    // e.g. 'DejaVu Sans'
    FilePath:   RawUtf8;    // absolute path to the font file
    Bold:       boolean;
    Italic:     boolean;
  end;
  TFontFileMapDynArray = array of TFontFileMap;

/// scan a directory tree for .ttf/.otf files and populate a font map
procedure ScanFontsDir(const ADir: string; var AMap: TFontFileMapDynArray);

/// find the best matching font file for the given face name and style
// - returns empty string if not found
function FindFontFile(const AMap: TFontFileMapDynArray;
  const AFaceName: RawUtf8; ABold, AItalic: boolean): RawUtf8;


{ ****************** Font Collections and Face Sizing }

type
  /// the record behind a TFontHandle of TFreeTypeFontProvider
  // - public so that mormot.lib.harfbuzz can reach the FT_Face
  TFreeTypeFont = record
    Face:         FT_Face;   // FreeType2 face handle
    FilePath:     RawUtf8;   // absolute path (for diagnostics)
    UnitsPerEM:   integer;   // face^.units_per_EM
    Ascent:       integer;   // scaled ascender  (design units * 1000 / UPM)
    Descent:      integer;   // scaled descender (negative)
    Height:       integer;
    IsFixedWidth: boolean;
    FaceIndex:    integer;   // index of the face opened within a .ttc
    Sfnt:         RawByteString; // cached standalone sfnt built from a .ttc
    SfntChecked:  boolean;   // true once the file has been tested for 'ttcf'
  end;
  PFreeTypeFont = ^TFreeTypeFont;

/// size the FT_Face so that one em equals exactly 1000 units
// - hb_ft_font_create() derives the HarfBuzz scale from ft_face^.size^.metrics,
//   which stays zero on a face that was never sized: every shaped advance then
//   comes back as 0.  Sizing to 1000 units per em makes HarfBuzz return 26.6
//   values which are just the PDF-unit widths shifted by 6 bits
// - CreateFont() does not size the face because the other entry points all use
//   FT_LOAD_NO_SCALE or read design-unit fields, so they are unaffected by this
function FreeTypeSetEmSize1000(AFont: PFreeTypeFont): boolean;


{ ****************** IFontProvider, IFontEnumerator and IFontDC Implementation }

type
  /// FreeType2 implementation of IFontProvider
  // - each TFontHandle is a PFreeTypeFont
  TFreeTypeFontProvider = class(TInterfacedObject, IFontProvider)
  private
    fFontMap: TFontFileMapDynArray;
  public
    constructor Create;
    function CreateFont(const Request: TFontRequest): TFontHandle;
    procedure DeleteFont(Font: TFontHandle);
    function SelectFont(DC: TFontDC; Font: TFontHandle): TFontHandle;
    function GetTextMetrics(DC: TFontDC; out Metrics: TFontMetrics): boolean;
    function GetOutlineMetrics(DC: TFontDC;
      out Metrics: TFontOutlineMetrics): boolean;
    function GetCharAbcWidths(DC: TFontDC; FirstChar, LastChar: cardinal;
      out Widths: TFontCharAbcArray): boolean;
    function GetFontData(DC: TFontDC; TableTag, Offset: cardinal;
      Buffer: pointer; BufferSize: cardinal): cardinal;
    function FontDataError: cardinal;
    function GetFaceFile(DC: TFontDC; out Face: RawByteString): boolean;
  end;

  /// FreeType2 implementation of IFontEnumerator
  TFreeTypeFontEnumerator = class(TInterfacedObject, IFontEnumerator)
  private
    fFontMap: TFontFileMapDynArray;
    procedure BuildFontMap;
  public
    constructor Create;
    procedure EnumTrueTypeFonts(DC: TFontDC; var List: TRawUtf8DynArray);
  end;

  /// FreeType2 implementation of IFontDC - transitional, as IFontDC
  TFreeTypeFontDC = class(TInterfacedObject, IFontDC)
  public
    function CreateDC: TFontDC;
    procedure DeleteDC(DC: TFontDC);
    function GetScreenLogPixels(DC: TFontDC): integer;
  end;


implementation


{ ****************** FreeType2 Minimal API Bindings }

const
  /// the library names, tried in this order
  // - Homebrew installs to /opt/homebrew on Apple Silicon (ARM64), which is
  // not in the default dyld search path
  FREETYPE_LIB_NAMES: array[0 .. {$ifdef OSDARWIN} 5 {$else} 1 {$endif}] of TFileName = (
    {$ifdef OSDARWIN}
    'libfreetype.6.dylib',
    'libfreetype.dylib',
    '/opt/homebrew/lib/libfreetype.6.dylib',
    '/opt/homebrew/lib/libfreetype.dylib',
    '/usr/local/lib/libfreetype.6.dylib',
    '/usr/local/lib/libfreetype.dylib');
    {$else}
    'libfreetype.so.6',
    'libfreetype.so');
    {$endif OSDARWIN}

  /// the entries of TFreeTypeLib, in the order of its fields
  FREETYPE_ENTRIES: array[0 .. 7] of PAnsiChar = (
    'Init_FreeType',
    'Done_FreeType',
    'New_Face',
    'Done_Face',
    'Set_Char_Size',
    'Load_Char',
    'Load_Sfnt_Table',
    nil);

function TFreeTypeLib.Loaded: boolean;
begin
  result := (self <> nil) and
            fLoaded;
end;

function LoadFreeType: boolean;
var
  lib: TFreeTypeLib;
  err: string;
begin
  result := FreeType.Loaded;
  if result then
    exit;
  lib := TFreeTypeLib.Create;
  if lib.TryLoadLibrary(FREETYPE_LIB_NAMES) and
     lib.ResolveAll(@FREETYPE_ENTRIES, @@lib.Init, 'FT_', nil, @err) and
     (lib.Init(lib.FTLibrary) = 0) then
  begin
    lib.fLoaded := true;
    FreeType := lib;
    result := true;
  end
  else
    lib.Free; // the next call tries again
end;


{ ****************** Font Files Discovery }

procedure ScanFontsDir(const ADir: string; var AMap: TFontFileMapDynArray);
var
  sr:    TSearchRec;
  ext:   string;
  entry: TFontFileMap;
  face:  FT_Face;
  fname: RawUtf8;
  n:     integer;
begin
  if not DirectoryExists(ADir) then
    exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        continue;
      if sr.Attr and faDirectory <> 0 then
        ScanFontsDir(IncludeTrailingPathDelimiter(ADir) + sr.Name, AMap)
      else
      begin
        ext := SysUtils.LowerCase(ExtractFileExt(sr.Name));
        if (ext = '.ttf') or (ext = '.otf') or (ext = '.ttc') then
        begin
          if not FreeType.Loaded then
            continue;
          face := nil;
          if FreeType.NewFace(FreeType.FTLibrary,
             PAnsiChar(AnsiString(IncludeTrailingPathDelimiter(ADir) + sr.Name)),
             0, face) = 0 then
          begin
            fname := RawUtf8(PFT_FaceRec(face)^.family_name);
            n := Length(AMap);
            SetLength(AMap, n + 1);
            entry.FamilyName := fname;
            StringToUTF8(IncludeTrailingPathDelimiter(ADir) + sr.Name,
              entry.FilePath);
            if PFT_FaceRec(face)^.style_name <> nil then
            begin
              entry.Bold   := Pos('Bold',   string(PFT_FaceRec(face)^.style_name)) > 0;
              entry.Italic := Pos('Italic', string(PFT_FaceRec(face)^.style_name)) > 0;
            end
            else
            begin
              entry.Bold   := false;
              entry.Italic := false;
            end;
            AMap[n] := entry;
            FreeType.DoneFace(face);
          end;
        end;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

function FindFontFile(const AMap: TFontFileMapDynArray;
  const AFaceName: RawUtf8; ABold, AItalic: boolean): RawUtf8;
var
  i:     integer;
  best:  integer;
  score: integer;
  s:     integer;
begin
  result := '';
  best   := -1;
  score  := -1;
  for i := 0 to high(AMap) do
  begin
    if SameTextU(AMap[i].FamilyName, AFaceName) then
    begin
      s := 0;
      if AMap[i].Bold   = ABold   then inc(s, 2);
      if AMap[i].Italic = AItalic then inc(s, 2);
      if s > score then
      begin
        score := s;
        best  := i;
      end;
    end;
  end;
  if best >= 0 then
    result := AMap[best].FilePath;
end;


{ ****************** Font Collections and Face Sizing }

// scale design units to "GDI units" (design units * 1000 / UPM)

function MulDiv(nNumber, nNumerator, nDenominator: integer): integer;
  {$ifdef HASINLINE} inline; {$endif}
begin
  if nDenominator = 0 then
    result := -1
  else
    result := (int64(nNumber) * nNumerator + nDenominator div 2) div nDenominator;
end;

function ScaleDesignUnit(AValue, AUnitsPerEM: integer): integer;
begin
  if AUnitsPerEM <= 0 then
    result := AValue
  else
    result := MulDiv(AValue, 1000, AUnitsPerEM);
end;

function FreeTypeSetEmSize1000(AFont: PFreeTypeFont): boolean;
begin
  result := FreeType.Loaded and
            (AFont <> nil) and
            (AFont^.Face <> nil) and
            // 1000 in 26.6 fixed point, at 72 dpi -> ppem = 1000 = one em
            (FreeType.SetCharSize(AFont^.Face, 0, 1000 shl 6, 72, 72) = 0);
end;


{ ****************** IFontProvider, IFontEnumerator and IFontDC Implementation }

type
  /// the record behind a TFontDC of TFreeTypeFontDC
  TFreeTypeDC = record
    Current: PFreeTypeFont;
  end;
  PFreeTypeDC = ^TFreeTypeDC;

{ TFreeTypeFontProvider }

constructor TFreeTypeFontProvider.Create;
begin
  inherited Create;
  // Build a font map so CreateFont can find files
  if FreeType.Loaded then
  begin
    {$ifdef OSDARWIN}
    ScanFontsDir('/Library/Fonts', fFontMap);
    ScanFontsDir('/System/Library/Fonts', fFontMap);
    ScanFontsDir(GetEnvironmentVariable('HOME') + '/Library/Fonts', fFontMap);
    {$else}
    ScanFontsDir('/usr/share/fonts', fFontMap);
    ScanFontsDir('/usr/local/share/fonts', fFontMap);
    ScanFontsDir(GetEnvironmentVariable('HOME') + '/.fonts', fFontMap);
    ScanFontsDir(GetEnvironmentVariable('HOME') + '/.local/share/fonts', fFontMap);
    ScanFontsDir('/system/fonts', fFontMap); // Android
    {$endif OSDARWIN}
  end;
end;

function TFreeTypeFontProvider.CreateFont(
  const Request: TFontRequest): TFontHandle;
var
  faceName: RawUtf8;
  filePath: RawUtf8;
  face:     FT_Face;
  ctx:      PFreeTypeFont;
  faceRec:  PFT_FaceRec;
  bold, italic: boolean;
begin
  result := nil;
  if not FreeType.Loaded then
    exit;
  bold   := Request.Weight >= 600;
  italic := Request.Italic <> 0;
  faceName := SynUnicodeToUtf8(Request.FaceName);
  filePath := FindFontFile(fFontMap, faceName, bold, italic);
  if filePath = '' then
  begin
    // Fallback: try DejaVu Sans
    filePath := FindFontFile(fFontMap, 'DejaVu Sans', bold, italic);
    if filePath = '' then
      filePath := FindFontFile(fFontMap, 'DejaVuSans', bold, italic);
    if filePath = '' then
      filePath := FindFontFile(fFontMap, 'Roboto', bold, italic); // Android
    if filePath = '' then
      exit; // no font found at all
  end;
  face := nil;
  if FreeType.NewFace(FreeType.FTLibrary, PAnsiChar(AnsiString(filePath)),
     0, face) <> 0 then
    exit;
  // GetCharAbcWidths will use FT_LOAD_NO_SCALE to get raw design units,
  // so SetCharSize is not needed here anymore
  faceRec := PFT_FaceRec(face);
  New(ctx);
  ctx^.Face         := face;
  ctx^.FilePath     := filePath;
  ctx^.UnitsPerEM   := faceRec^.units_per_EM;
  ctx^.Ascent       := ScaleDesignUnit(faceRec^.ascender,    ctx^.UnitsPerEM);
  ctx^.Descent      := ScaleDesignUnit(faceRec^.descender,   ctx^.UnitsPerEM);
  ctx^.Height       := ScaleDesignUnit(faceRec^.height,      ctx^.UnitsPerEM);
  ctx^.IsFixedWidth := (faceRec^.face_flags and FT_FACE_FLAG_FIXED_WIDTH) <> 0;
  ctx^.FaceIndex    := 0; // FT_New_Face() above always opens the first face
  ctx^.SfntChecked  := false; // New() initializes managed fields only
  result := TFontHandle(ctx);
end;

procedure TFreeTypeFontProvider.DeleteFont(Font: TFontHandle);
var
  ctx: PFreeTypeFont;
begin
  if Font = nil then
    exit;
  ctx := PFreeTypeFont(Font);
  if ctx^.Face <> nil then
    FreeType.DoneFace(ctx^.Face);
  Dispose(ctx);
end;

function TFreeTypeFontProvider.SelectFont(DC: TFontDC;
  Font: TFontHandle): TFontHandle;
var
  dc_: PFreeTypeDC;
begin
  dc_ := PFreeTypeDC(DC);
  result := TFontHandle(dc_^.Current);
  dc_^.Current := PFreeTypeFont(Font);
end;

function TFreeTypeFontProvider.GetTextMetrics(DC: TFontDC;
  out Metrics: TFontMetrics): boolean;
var
  dc_: PFreeTypeDC;
  ctx: PFreeTypeFont;
  fr:  PFT_FaceRec;
begin
  result := false;
  dc_ := PFreeTypeDC(DC);
  if (dc_ = nil) or (dc_^.Current = nil) then
    exit;
  ctx := dc_^.Current;
  fr  := PFT_FaceRec(ctx^.Face);
  FillChar(Metrics, SizeOf(Metrics), 0);
  Metrics.tmAscent  := ctx^.Ascent;
  Metrics.tmDescent := -ctx^.Descent; // make positive like Windows
  Metrics.tmHeight  := Metrics.tmAscent + Metrics.tmDescent;
  Metrics.tmInternalLeading := 0;
  Metrics.tmExternalLeading := ScaleDesignUnit(fr^.height, ctx^.UnitsPerEM)
                                - Metrics.tmHeight;
  // Average char width ~ em-width / 2 (rough estimate)
  Metrics.tmAveCharWidth := ctx^.Ascent div 2;
  Metrics.tmMaxCharWidth := ctx^.Ascent;
  Metrics.tmWeight       := 400; // FW_NORMAL; caller sets bold separately
  Metrics.tmFirstChar    := WideChar(32);
  Metrics.tmLastChar     := WideChar(255);
  Metrics.tmDefaultChar  := WideChar(Ord('?'));
  Metrics.tmBreakChar    := WideChar(Ord(' '));
  Metrics.tmItalic       := 0;
  Metrics.tmCharSet      := 0; // ANSI_CHARSET
  if ctx^.IsFixedWidth then
    Metrics.tmPitchAndFamily := 0  // fixed pitch: bit 0 = 0
  else
    Metrics.tmPitchAndFamily := 1; // variable pitch: bit 0 = 1
  result := true;
end;

function TFreeTypeFontProvider.GetOutlineMetrics(DC: TFontDC;
  out Metrics: TFontOutlineMetrics): boolean;
var
  dc_: PFreeTypeDC;
  ctx: PFreeTypeFont;
  fr:  PFT_FaceRec;
begin
  result := false;
  dc_ := PFreeTypeDC(DC);
  if (dc_ = nil) or (dc_^.Current = nil) then
    exit;
  ctx := dc_^.Current;
  fr  := PFT_FaceRec(ctx^.Face);
  FillChar(Metrics, SizeOf(Metrics), 0);
  Metrics.otmSize     := SizeOf(Metrics);
  Metrics.otmAscent   := ctx^.Ascent;
  Metrics.otmDescent  := ctx^.Descent; // negative
  Metrics.otmLineGap  := Metrics.otmAscent - Metrics.otmDescent;
  Metrics.otmItalicAngle := 0;
  Metrics.otmrcFontBox.Left   := ScaleDesignUnit(fr^.bbox.xMin, ctx^.UnitsPerEM);
  Metrics.otmrcFontBox.Bottom := ScaleDesignUnit(fr^.bbox.yMin, ctx^.UnitsPerEM);
  Metrics.otmrcFontBox.Right  := ScaleDesignUnit(fr^.bbox.xMax, ctx^.UnitsPerEM);
  Metrics.otmrcFontBox.Top    := ScaleDesignUnit(fr^.bbox.yMax, ctx^.UnitsPerEM);
  Metrics.otmMacAscent  := Metrics.otmAscent;
  Metrics.otmMacDescent := Metrics.otmDescent;
  Metrics.otmEMSquare   := ctx^.UnitsPerEM;
  result := true;
end;

function TFreeTypeFontProvider.GetCharAbcWidths(DC: TFontDC;
  FirstChar, LastChar: cardinal; out Widths: TFontCharAbcArray): boolean;
var
  dc_:   PFreeTypeDC;
  ctx:   PFreeTypeFont;
  n, i:  integer;
  slot:  PFT_GlyphSlotRec;
  adv:   FT_Pos;
  lsb:   FT_Pos;   // left side bearing (A width)
  rsb:   FT_Pos;   // right side bearing (C width)
  code:  cardinal;
  a, c:  integer;
  total: integer;
begin
  result := false;
  dc_ := PFreeTypeDC(DC);
  if (dc_ = nil) or (dc_^.Current = nil) then
    exit;
  ctx := dc_^.Current;
  n := integer(LastChar) - integer(FirstChar) + 1;
  if n <= 0 then
    exit;
  SetLength(Widths, n);
  for i := 0 to n - 1 do
  begin
    FillChar(Widths[i], SizeOf(Widths[i]), 0);
    code := FirstChar + cardinal(i);
    // the caller asks for 32..255, i.e. WinAnsi byte values, because that is
    // what the Windows counterpart GetCharABCWidthsA takes - an ANSI call that
    // maps through the DC codepage. FT_Load_Char expects a Unicode code point,
    // so the byte has to be translated first: without this, 128..159 are read
    // as the unassigned C1 controls, miss the CMAP and silently return the
    // .notdef advance. That is what put the bullet (#$95 -> U+2022) and the
    // em dash (#$97 -> U+2014) into /Widths with a wrong value.
    if code <= high(byte) then
      code := WinAnsiConvert.AnsiToWide[code];
    // Use FT_LOAD_NO_SCALE to get raw design units (like faceRec^.ascender),
    // then apply uniform ScaleDesignUnit(value, UPM) across all metrics.
    if FreeType.LoadChar(ctx^.Face, code, FT_LOAD_NO_SCALE) = 0 then
    begin
      slot := PFT_GlyphSlotRec(PFT_FaceRec(ctx^.Face)^.glyph);
      // FreeType metrics in design units:
      // - horiBearingX = left side bearing (A)
      // - horiAdvance = total advance width (A + B + C)
      // - rsb = advance - (lsb + width)
      lsb := slot^.metrics.horiBearingX;
      adv := slot^.metrics.horiAdvance;
      // Calculate right side bearing
      // rsb = horiAdvance - horiBearingX - glyph_width
      rsb := adv - lsb - slot^.metrics.width;
      // the engine uses abcA + abcB + abcC as the advance width, and that sum
      // ends up in /Widths. Scaling the three parts on their own rounds three
      // times, so the sum could miss the scaled advance by up to 1.5 units -
      // enough to break ISO 14289-1 7.21.5, which allows 1. Scale the
      // advance once, and give abcB whatever the two bearings leave over, so
      // the sum is exact by construction.
      total := ScaleDesignUnit(adv, ctx^.UnitsPerEM);
      a := ScaleDesignUnit(lsb, ctx^.UnitsPerEM);
      c := ScaleDesignUnit(rsb, ctx^.UnitsPerEM);
      Widths[i].abcA := a;
      Widths[i].abcB := cardinal(total - a - c);
      Widths[i].abcC := c;
    end;
  end;
  result := true;
end;

function TFreeTypeFontProvider.GetFontData(DC: TFontDC;
  TableTag, Offset: cardinal; Buffer: pointer; BufferSize: cardinal): cardinal;
var
  dc_: PFreeTypeDC;
  ctx: PFreeTypeFont;
  len: FT_ULong;
  err: FT_Error;
begin
  result := FontDataError;
  dc_ := PFreeTypeDC(DC);
  if (dc_ = nil) or (dc_^.Current = nil) then
    exit;
  ctx := dc_^.Current;
  if TableTag = 0 then
  begin
    // "whole font file": for a .ttc this would return the entire collection,
    // which is not a valid /FontFile2 - hand out just the face we loaded
    if not ctx^.SfntChecked then
    begin
      ctx^.SfntChecked := true; // a plain .ttf is returned by FreeType as it is
      if ctx^.FilePath <> '' then
        ctx^.Sfnt := ExtractSfntFromTtc(
          StringFromFile(Utf8ToString(ctx^.FilePath)), ctx^.FaceIndex);
    end;
    if ctx^.Sfnt <> '' then
    begin
      result := length(ctx^.Sfnt);
      if Buffer <> nil then
        if BufferSize < result then
          result := FontDataError
        else
          MoveFast(pointer(ctx^.Sfnt)^, Buffer^, result);
      exit;
    end;
  end;
  len := BufferSize;
  // The PDF engine forms table tags as PCardinal(name)^ - a 4-char ASCII
  // name read as a little-endian DWORD (e.g. 'cmap' -> $70616D63).
  // FreeType uses big-endian tags (FT_MAKE_TAG: 'cmap' -> $636D6170).
  // bswap32 converts between the two; bswap32(0)=0 so tag=0
  // ("return whole font file") is passed through correctly.
  err := FreeType.LoadSfntTable(ctx^.Face, bswap32(TableTag), Offset,
    Buffer, len);
  if err <> 0 then
    exit;
  result := len;
end;

function TFreeTypeFontProvider.FontDataError: cardinal;
begin
  result := $FFFFFFFF;
end;

function TFreeTypeFontProvider.GetFaceFile(DC: TFontDC;
  out Face: RawByteString): boolean;
var
  size: cardinal;
begin
  // GetFontData(0) already extracts the face of a .ttc (FilePath set); a
  // collection it could not extract, or one loaded without a path, fails
  result := false;
  size := GetFontData(DC, 0, 0, nil, 0);
  if (size = FontDataError) or
     (size < 12) then
    exit;
  FastSetRawByteString(Face, nil, size);
  if (GetFontData(DC, 0, 0, pointer(Face), size) <> size) or
     (PCardinal(Face)^ = $66637474) then // 'ttcf' as little-endian
  begin
    Face := '';
    exit;
  end;
  result := true;
end;

{ TFreeTypeFontEnumerator }

constructor TFreeTypeFontEnumerator.Create;
begin
  inherited Create;
  BuildFontMap;
end;

procedure TFreeTypeFontEnumerator.BuildFontMap;
begin
  {$ifdef OSDARWIN}
  ScanFontsDir('/Library/Fonts', fFontMap);
  ScanFontsDir('/System/Library/Fonts', fFontMap);
  ScanFontsDir(GetEnvironmentVariable('HOME') + '/Library/Fonts', fFontMap);
  {$else}
  ScanFontsDir('/usr/share/fonts', fFontMap);
  ScanFontsDir('/usr/local/share/fonts', fFontMap);
  ScanFontsDir(GetEnvironmentVariable('HOME') + '/.fonts', fFontMap);
  ScanFontsDir(GetEnvironmentVariable('HOME') + '/.local/share/fonts', fFontMap);
  ScanFontsDir('/system/fonts', fFontMap); // Android
  {$endif OSDARWIN}
end;

procedure TFreeTypeFontEnumerator.EnumTrueTypeFonts(DC: TFontDC;
  var List: TRawUtf8DynArray);
var
  i: integer;
begin
  { Enumerate all fonts in fFontMap, but only add family names once (duplicates
    are filtered by AddRawUtf8 with true,true). The font variants (Bold, Italic)
    are found via CreateFont -> FindFontFile which matches against Bold/Italic flags. }
  for i := 0 to high(fFontMap) do
    AddRawUtf8(List, fFontMap[i].FamilyName, true, true);
end;

{ TFreeTypeFontDC }

function TFreeTypeFontDC.CreateDC: TFontDC;
var
  dc_: PFreeTypeDC;
begin
  New(dc_);
  dc_^.Current := nil;
  result := TFontDC(dc_);
end;

procedure TFreeTypeFontDC.DeleteDC(DC: TFontDC);
begin
  if DC <> nil then
    Dispose(PFreeTypeDC(DC));
end;

function TFreeTypeFontDC.GetScreenLogPixels(DC: TFontDC): integer;
begin
  result := FREETYPE_SCREEN_DPI;
end;


var
  // what this unit registered, so that only its own services are released
  RegisteredProvider: IFontProvider;
  RegisteredEnumerator: IFontEnumerator;
  RegisteredDC: IFontDC;

procedure RegisterFreeType;
begin
  RegisteredProvider := TFreeTypeFontProvider.Create;
  RegisteredEnumerator := TFreeTypeFontEnumerator.Create;
  RegisteredDC := TFreeTypeFontDC.Create;
  RegisterFontPlatform(RegisteredProvider, RegisteredEnumerator, RegisteredDC);
end;

procedure UnregisterFreeType;
begin
  // release the services before the library they call
  if FontProvider = RegisteredProvider then
    FontProvider := nil;
  if FontEnumerator = RegisteredEnumerator then
    FontEnumerator := nil;
  if FontDC = RegisteredDC then
    FontDC := nil;
  RegisteredProvider := nil;
  RegisteredEnumerator := nil;
  RegisteredDC := nil;
  if FreeType.Loaded then
    FreeType.Done(FreeType.FTLibrary);
  FreeAndNil(FreeType); // calls FreeLib
end;


initialization
  if LoadFreeType then
    RegisterFreeType;

finalization
  UnregisterFreeType;

{$endif OSWINDOWS}

end.
