/// low-level access to the HarfBuzz library, for text shaping and font subsetting
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.lib.harfbuzz;

{
  *****************************************************************************

   HarfBuzz Text Shaping and Font Subsetting for POSIX
   - HarfBuzz Minimal API Bindings (dynamic loading)
   - IFontShaper Implementation, using the mormot.lib.freetype face
   - hb-subset Minimal API Bindings (dynamic loading)
   - IFontSubsetter Implementation, retaining the glyph IDs

   The initialization section registers FontShaper when libharfbuzz.so.0 /
   libharfbuzz.0.dylib loads, and FontSubsetter when libharfbuzz-subset and
   libharfbuzz (HarfBuzz 2.9+) load: each library is optional.

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
  mormot.core.base,
  mormot.core.os,
  mormot.lib.core,
  mormot.lib.freetype;


{ ****************** HarfBuzz Minimal API Bindings }

/// load the HarfBuzz shared library dynamically; returns false if not found
function LoadHarfBuzz: boolean;


{ ****************** hb-subset Minimal API Bindings }

const
  /// hb_subset_flags_t values from harfbuzz/hb-subset.h (HarfBuzz 10.2.0)
  HB_SUBSET_FLAGS_NO_HINTING     = $00000001;
  HB_SUBSET_FLAGS_RETAIN_GIDS    = $00000002;
  HB_SUBSET_FLAGS_NOTDEF_OUTLINE = $00000040;

var
  /// flags passed to hb_subset_input_set_flags()
  // - RETAIN_GIDS is mandatory: the PDF engine writes the original glyph IDs
  // - NOTDEF_OUTLINE keeps the .notdef box, so a missing glyph stays visible
  // - NO_HINTING drops the TrueType bytecode, which PDF viewers hardly use
  HbSubsetFlags: cardinal = HB_SUBSET_FLAGS_RETAIN_GIDS or
    HB_SUBSET_FLAGS_NOTDEF_OUTLINE or HB_SUBSET_FLAGS_NO_HINTING;
  /// drop the GSUB/GPOS/GDEF tables from the subset
  // - a PDF viewer never shapes text, and the glyph set of the request already
  // holds every shaped glyph that was drawn
  HbSubsetDropLayoutTables: boolean = true;

/// load libharfbuzz-subset and libharfbuzz dynamically
// - returns false if a library or one of the required symbols is missing,
// e.g. with a HarfBuzz older than 2.9 which lacks hb_subset_or_fail()
function LoadHarfBuzzSubset: boolean;


implementation


{ ****************** HarfBuzz Minimal API Bindings }

type
  hb_font_t      = pointer;
  hb_buffer_t    = pointer;
  hb_direction_t = integer;
  hb_codepoint_t = cardinal;
  hb_position_t  = integer;
  hb_mask_t      = cardinal;

  /// HarfBuzz glyph info record (matches hb_glyph_info_t in harfbuzz/hb.h)
  hb_glyph_info_t = packed record
    codepoint: hb_codepoint_t; // shaped glyph ID (not a Unicode codepoint)
    mask:      hb_mask_t;
    cluster:   cardinal;       // index of corresponding source character
    var1_:     cardinal;       // HarfBuzz-internal
    var2_:     cardinal;       // HarfBuzz-internal
  end;
  // array pointer for indexed access to hb_buffer_get_glyph_infos result
  hb_glyph_info_array     = array[0..high(integer) div SizeOf(hb_glyph_info_t) - 1]
                              of hb_glyph_info_t;
  Phb_glyph_info_array    = ^hb_glyph_info_array;

  /// HarfBuzz glyph position record (matches hb_glyph_position_t in harfbuzz/hb.h)
  hb_glyph_position_t = packed record
    x_advance: hb_position_t; // horizontal advance in font units
    y_advance: hb_position_t;
    x_offset:  hb_position_t;
    y_offset:  hb_position_t;
    var_:      integer;        // HarfBuzz-internal
  end;
  // array pointer for indexed access to hb_buffer_get_glyph_positions result
  hb_glyph_position_array  = array[0..high(integer) div SizeOf(hb_glyph_position_t) - 1]
                               of hb_glyph_position_t;
  Phb_glyph_position_array = ^hb_glyph_position_array;

const
  /// hb_direction_t values from harfbuzz/hb-common.h
  HB_DIRECTION_LTR = 4;
  HB_DIRECTION_RTL = 5;

  /// FT_LOAD_NO_HINTING keeps the advances free of grid-fitting distortion
  // - do NOT use FT_LOAD_NO_SCALE here: HarfBuzz dropped its "return raw design
  //   units" behaviour for that flag, and now always multiplies the advance by
  //   a factor derived from the font scale, which yields 0 for every glyph
  HB_FT_LOAD_NO_HINTING = 2; // = FT_LOAD_NO_HINTING = 1 shl 1

// HarfBuzz function pointer types (cdecl, all from libharfbuzz)
type
  Thb_ft_font_create = function(
    face: FT_Face; destroy_: pointer): hb_font_t; cdecl;
  Thb_ft_font_set_load_flags = procedure(
    font: hb_font_t; load_flags: integer); cdecl;
  Thb_font_destroy = procedure(
    font: hb_font_t); cdecl;
  Thb_buffer_create = function: hb_buffer_t; cdecl;
  Thb_buffer_destroy = procedure(
    buffer: hb_buffer_t); cdecl;
  Thb_buffer_add_utf16 = procedure(
    buffer: hb_buffer_t; text: PWideChar; text_length: integer;
    item_offset: cardinal; item_length: integer); cdecl;
  Thb_buffer_set_direction = procedure(
    buffer: hb_buffer_t; direction: hb_direction_t); cdecl;
  Thb_buffer_guess_segment_properties = procedure(
    buffer: hb_buffer_t); cdecl;
  Thb_shape = procedure(
    font: hb_font_t; buffer: hb_buffer_t;
    features: pointer; num_features: cardinal); cdecl;
  Thb_buffer_get_glyph_infos = function(
    buffer: hb_buffer_t; out length: cardinal): Phb_glyph_info_array; cdecl;
  Thb_buffer_get_glyph_positions = function(
    buffer: hb_buffer_t; out length: cardinal): Phb_glyph_position_array; cdecl;

  /// the loaded libharfbuzz and the function pointers of the shaper
  // - the function fields are resolved in their declaration order
  THarfBuzzLib = class(TSynLibrary)
  protected
    fLoaded: boolean;
  public
    ft_font_create:  Thb_ft_font_create;
    font_destroy:    Thb_font_destroy;
    buffer_create:   Thb_buffer_create;
    buffer_destroy:  Thb_buffer_destroy;
    buffer_add_utf16: Thb_buffer_add_utf16;
    buffer_set_direction: Thb_buffer_set_direction;
    buffer_guess_segment_properties: Thb_buffer_guess_segment_properties;
    shape:           Thb_shape;
    buffer_get_glyph_infos: Thb_buffer_get_glyph_infos;
    buffer_get_glyph_positions: Thb_buffer_get_glyph_positions;
    // optional - available since HarfBuzz 0.9.5; used to set FT_LOAD_NO_HINTING
    ft_font_set_load_flags: Thb_ft_font_set_load_flags;
    /// true once the library is loaded - false on nil
    function Loaded: boolean;
      {$ifdef HASINLINE} inline; {$endif}
  end;

const
  /// the libharfbuzz names for the shaper, tried in this order
  HARFBUZZ_LIB_NAMES: array[0 .. {$ifdef OSDARWIN} 5 {$else} 1 {$endif}] of TFileName = (
    {$ifdef OSDARWIN}
    'libharfbuzz.0.dylib',
    'libharfbuzz.dylib',
    '/opt/homebrew/lib/libharfbuzz.0.dylib',
    '/opt/homebrew/lib/libharfbuzz.dylib',
    '/usr/local/lib/libharfbuzz.0.dylib',
    '/usr/local/lib/libharfbuzz.dylib');
    {$else}
    'libharfbuzz.so.0',
    'libharfbuzz.so');
    {$endif OSDARWIN}

  /// the entries of THarfBuzzLib, in the order of its fields
  HARFBUZZ_ENTRIES: array[0 .. 11] of PAnsiChar = (
    'ft_font_create',
    'font_destroy',
    'buffer_create',
    'buffer_destroy',
    'buffer_add_utf16',
    'buffer_set_direction',
    'buffer_guess_segment_properties',
    'shape',
    'buffer_get_glyph_infos',
    'buffer_get_glyph_positions',
    '?ft_font_set_load_flags',
    nil);

var
  HarfBuzz: THarfBuzzLib;

function THarfBuzzLib.Loaded: boolean;
begin
  result := (self <> nil) and
            fLoaded;
end;

function LoadHarfBuzz: boolean;
var
  lib: THarfBuzzLib;
  err: string;
begin
  result := HarfBuzz.Loaded;
  if result then
    exit;
  lib := THarfBuzzLib.Create;
  if lib.TryLoadLibrary(HARFBUZZ_LIB_NAMES) and
     lib.ResolveAll(@HARFBUZZ_ENTRIES, @@lib.ft_font_create, 'hb_', nil, @err) then
  begin
    lib.fLoaded := true;
    HarfBuzz := lib;
    result := true;
  end
  else
    lib.Free; // the next call tries again
end;


{ ****************** IFontShaper Implementation }

function From26Dot6(AValue: hb_position_t): integer;
  {$ifdef HASINLINE} inline; {$endif}
begin // round half away from zero, the sign being kept for the offsets
  if AValue >= 0 then
    result := (AValue + 32) shr 6
  else
    result := -((32 - AValue) shr 6);
end;

// true if the text holds a character of a script that needs OpenType shaping:
// what Uniscribe's ScriptItemize marks as complex, so that a Latin text is
// left to the caller unshaped on both platforms
function NeedsShaping(Text: PWideChar; Len: integer): boolean;
var
  i: integer;
  c: cardinal;
begin
  result := true;
  for i := 0 to Len - 1 do
  begin
    c := ord(Text[i]);
    if ((c >= $0590) and (c <= $109F)) or // Hebrew, Arabic, Indic ... Myanmar
       ((c >= $1780) and (c <= $18AF)) or // Khmer, Mongolian
       ((c >= $A800) and (c <= $ABFF)) or // Syloti Nagri ... Meetei Mayek
       ((c >= $FB1D) and (c <= $FDFF)) or // Hebrew and Arabic presentation forms A
       ((c >= $FE70) and (c <= $FEFE)) then // Arabic presentation forms B
      exit;
  end;
  result := false;
end;

type
  /// HarfBuzz implementation of IFontShaper
  // - shapes the whole text in one call: one fskShaped run, every glyph kept
  // - returns false for a text which is not RightToLeft and has no character
  // of a script that needs shaping (NeedsShaping)
  THarfBuzzShaper = class(TInterfacedObject, IFontShaper)
  public
    function Shape(Text: PWideChar; Len: integer; Font: TFontHandle;
      RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
  end;

function THarfBuzzShaper.Shape(Text: PWideChar; Len: integer;
  Font: TFontHandle; RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
var
  ctx:       PFreeTypeFont;
  font_:     hb_font_t;
  buf:       hb_buffer_t;
  infos:     Phb_glyph_info_array;
  positions: Phb_glyph_position_array;
  count:     cardinal;
  i:         integer;
begin
  result := false;
  Runs   := nil;
  if not HarfBuzz.Loaded or (Font = nil) or
     (Text = nil) or (Len <= 0) or
     not (RightToLeft or NeedsShaping(Text, Len)) then
    exit;
  ctx := PFreeTypeFont(Font);
  if ctx^.Face = nil then
    exit;
  // hb_ft_font_create() copies the scale out of ft_face^.size^.metrics, so the
  // face must be sized first or every advance comes back as 0
  if not FreeTypeSetEmSize1000(ctx) then
    exit;
  font_ := HarfBuzz.ft_font_create(ctx^.Face, nil);
  if font_ = nil then
    exit;
  if Assigned(HarfBuzz.ft_font_set_load_flags) then
    HarfBuzz.ft_font_set_load_flags(font_, HB_FT_LOAD_NO_HINTING);
  buf := HarfBuzz.buffer_create;
  try
    HarfBuzz.buffer_add_utf16(buf, Text, Len, 0, -1);
    // RTL is forced; otherwise guess_segment_properties takes the direction
    // from the script, as Uniscribe's itemizer does - a forced LTR would
    // shape Arabic in the wrong order
    if RightToLeft then
      HarfBuzz.buffer_set_direction(buf, HB_DIRECTION_RTL);
    HarfBuzz.buffer_guess_segment_properties(buf);
    HarfBuzz.shape(font_, buf, nil, 0);
    count     := 0;
    infos     := HarfBuzz.buffer_get_glyph_infos(buf, count);
    positions := HarfBuzz.buffer_get_glyph_positions(buf, count);
    if (count = 0) or (infos = nil) or (positions = nil) then
      exit;
    SetLength(Runs, 1);
    with Runs[0] do
    begin
      Kind      := fskShaped;
      Outcome   := fsoDone;
      TextStart := 0;
      TextLen   := Len;
      SetLength(Glyphs,   count);
      SetLength(Advances, count);
      SetLength(Offsets,  count);
      SetLength(YOffsets, count);
      SetLength(Clusters, count);
      for i := 0 to integer(count) - 1 do
      begin
        Glyphs[i]   := word(infos[i].codepoint);
        Clusters[i] := integer(infos[i].cluster);
        // one em = 1000 units, so the 26.6 values are PDF units shifted by 6 bits
        Advances[i] := From26Dot6(positions[i].x_advance);
        Offsets[i]  := From26Dot6(positions[i].x_offset);
        YOffsets[i] := From26Dot6(positions[i].y_offset);
      end;
    end;
    result := true;
  finally
    HarfBuzz.buffer_destroy(buf);
    HarfBuzz.font_destroy(font_);
  end;
end;


{ ****************** hb-subset Minimal API Bindings }

type
  hb_blob_t         = pointer;
  hb_face_t         = pointer;
  hb_set_t          = pointer;
  hb_subset_input_t = pointer;

const
  /// hb_memory_mode_t from harfbuzz/hb-blob.h
  HB_MEMORY_MODE_READONLY = 1;
  /// hb_subset_sets_t from harfbuzz/hb-subset.h
  HB_SUBSET_SETS_DROP_TABLE_TAG = 3;
  /// HB_TAG() values of the OpenType layout tables
  HB_TAG_GSUB = $47535542;
  HB_TAG_GPOS = $47504F53;
  HB_TAG_GDEF = $47444546;

// hb-subset function pointer types (cdecl)
type
  Thb_blob_create = function(data: PAnsiChar; length: cardinal;
    mode: integer; user_data, destroy_: pointer): hb_blob_t; cdecl;
  Thb_blob_destroy = procedure(blob: hb_blob_t); cdecl;
  Thb_blob_get_data = function(blob: hb_blob_t;
    out length: cardinal): PAnsiChar; cdecl;
  Thb_face_create = function(blob: hb_blob_t; index: cardinal): hb_face_t; cdecl;
  Thb_face_destroy = procedure(face: hb_face_t); cdecl;
  Thb_face_reference_blob = function(face: hb_face_t): hb_blob_t; cdecl;
  Thb_set_add = procedure(set_: hb_set_t; codepoint: cardinal); cdecl;
  Thb_subset_input_create_or_fail = function: hb_subset_input_t; cdecl;
  Thb_subset_input_destroy = procedure(input: hb_subset_input_t); cdecl;
  Thb_subset_input_get_set = function(input: hb_subset_input_t): hb_set_t; cdecl;
  Thb_subset_input_set = function(input: hb_subset_input_t;
    set_type: integer): hb_set_t; cdecl;
  Thb_subset_input_set_flags = procedure(input: hb_subset_input_t;
    value: cardinal); cdecl;
  Thb_subset_or_fail = function(source: hb_face_t;
    input: hb_subset_input_t): hb_face_t; cdecl;

  /// the libharfbuzz functions used by the subsetter
  // - the function fields are resolved in their declaration order
  // - loaded on its own: the subsetter does not depend on the shaper
  THarfBuzzSubsetCoreLib = class(TSynLibrary)
  public
    blob_create: Thb_blob_create;
    blob_destroy: Thb_blob_destroy;
    blob_get_data: Thb_blob_get_data;
    face_create: Thb_face_create;
    face_destroy: Thb_face_destroy;
    face_reference_blob: Thb_face_reference_blob;
    set_add: Thb_set_add;
  end;

  /// the loaded libharfbuzz-subset and its function pointers
  // - hb_blob_*, hb_face_* and hb_set_* live in libharfbuzz, not in
  // libharfbuzz-subset, so both libraries are opened: Core holds the first
  THarfBuzzSubsetLib = class(TSynLibrary)
  protected
    fLoaded: boolean;
    fCore: THarfBuzzSubsetCoreLib;
  public
    input_create_or_fail: Thb_subset_input_create_or_fail;
    input_destroy: Thb_subset_input_destroy;
    input_unicode_set: Thb_subset_input_get_set;
    input_glyph_set: Thb_subset_input_get_set;
    input_set: Thb_subset_input_set;
    input_set_flags: Thb_subset_input_set_flags;
    subset_or_fail: Thb_subset_or_fail;
    destructor Destroy; override;
    /// true once both libraries are loaded - false on nil
    function Loaded: boolean;
      {$ifdef HASINLINE} inline; {$endif}
    /// the libharfbuzz part
    property Core: THarfBuzzSubsetCoreLib
      read fCore;
  end;

const
  /// the libharfbuzz names for the subsetter, tried in this order
  HBSUBSET_CORE_LIB_NAMES: array[0 .. {$ifdef OSDARWIN} 2 {$else} 1 {$endif}] of TFileName = (
    {$ifdef OSDARWIN}
    'libharfbuzz.0.dylib',
    '/opt/homebrew/lib/libharfbuzz.0.dylib',
    '/usr/local/lib/libharfbuzz.0.dylib');
    {$else}
    'libharfbuzz.so.0',
    'libharfbuzz.so');
    {$endif OSDARWIN}

  /// the libharfbuzz-subset names, tried in this order
  HBSUBSET_LIB_NAMES: array[0 .. {$ifdef OSDARWIN} 2 {$else} 1 {$endif}] of TFileName = (
    {$ifdef OSDARWIN}
    'libharfbuzz-subset.0.dylib',
    '/opt/homebrew/lib/libharfbuzz-subset.0.dylib',
    '/usr/local/lib/libharfbuzz-subset.0.dylib');
    {$else}
    'libharfbuzz-subset.so.0',
    'libharfbuzz-subset.so');
    {$endif OSDARWIN}

  /// the entries of THarfBuzzSubsetCoreLib, in the order of its fields
  HBSUBSET_CORE_ENTRIES: array[0 .. 7] of PAnsiChar = (
    'blob_create',
    'blob_destroy',
    'blob_get_data',
    'face_create',
    'face_destroy',
    'face_reference_blob',
    'set_add',
    nil);

  /// the entries of THarfBuzzSubsetLib, in the order of its fields
  // - no partial mode: HarfBuzz < 2.9 has only the deprecated subset API
  HBSUBSET_ENTRIES: array[0 .. 7] of PAnsiChar = (
    'input_create_or_fail',
    'input_destroy',
    'input_unicode_set',
    'input_glyph_set',
    'input_set',
    'input_set_flags',
    'or_fail',
    nil);

var
  HbSubset: THarfBuzzSubsetLib;

destructor THarfBuzzSubsetLib.Destroy;
begin
  fCore.Free;
  inherited Destroy;
end;

function THarfBuzzSubsetLib.Loaded: boolean;
begin
  result := (self <> nil) and
            fLoaded;
end;

procedure UnloadHarfBuzzSubset;
begin
  FreeAndNil(HbSubset); // calls FreeLib on both libraries
end;

function LoadHarfBuzzSubset: boolean;
var
  lib: THarfBuzzSubsetLib;
  err: string;
begin
  result := HbSubset.Loaded;
  if result then
    exit;
  lib := THarfBuzzSubsetLib.Create;
  lib.fCore := THarfBuzzSubsetCoreLib.Create;
  if lib.fCore.TryLoadLibrary(HBSUBSET_CORE_LIB_NAMES) and
     lib.TryLoadLibrary(HBSUBSET_LIB_NAMES) and
     lib.fCore.ResolveAll(@HBSUBSET_CORE_ENTRIES, @@lib.fCore.blob_create,
       'hb_', nil, @err) and
     lib.ResolveAll(@HBSUBSET_ENTRIES, @@lib.input_create_or_fail,
       'hb_subset_', nil, @err) then
  begin
    lib.fLoaded := true;
    HbSubset := lib;
    result := true;
  end
  else
    lib.Free; // the next call tries again
end;


{ ****************** IFontSubsetter Implementation }

type
  /// hb-subset implementation of IFontSubsetter
  // - Font is not used: the caller hands a face already extracted from a .ttc
  THarfBuzzSubsetter = class(TInterfacedObject, IFontSubsetter)
  public
    function Subset(const Face: RawByteString; const Request: TFontSubsetRequest;
      Font: TFontHandle; out Output: RawByteString): boolean;
    /// false: the request holds WinAnsi code points, while a symbol font maps
    // its glyphs at U+F0xx - hb-subset would drop them
    function SupportsSymbolic: boolean;
  end;

function THarfBuzzSubsetter.SupportsSymbolic: boolean;
begin
  result := false;
end;

// both outline flavours are embeddable: glyf goes to /FontFile2, CFF to
// /FontFile3 with /Subtype /OpenType - the caller tells them apart by the
// sfnt signature of the subset, which hb-subset preserves
function IsEmbeddableOutlines(const AFace: RawByteString): boolean;
begin
  result := (length(AFace) > 12) and
            ((copy(AFace, 1, 4) = #0#1#0#0) or
             (copy(AFace, 1, 4) = 'true') or
             (copy(AFace, 1, 4) = 'OTTO'));
end;

function THarfBuzzSubsetter.Subset(const Face: RawByteString;
  const Request: TFontSubsetRequest; Font: TFontHandle;
  out Output: RawByteString): boolean;
var
  blob, subblob: hb_blob_t;
  face_, subface: hb_face_t;
  input: hb_subset_input_t;
  s: hb_set_t;
  data: PAnsiChar;
  len: cardinal;
  i: PtrInt;
begin
  result := false;
  Output := '';
  if not HbSubset.Loaded or
     not IsEmbeddableOutlines(Face) then
    exit;
  with HbSubset, HbSubset.Core do
  begin
    // READONLY: Face outlives the blob, which is destroyed below
    blob := blob_create(pointer(Face), length(Face), HB_MEMORY_MODE_READONLY,
      nil, nil);
    face_ := face_create(blob, 0); // a .ttc face was already extracted
    input := input_create_or_fail;
    subface := nil;
    try
      if input = nil then
        exit;
      s := input_unicode_set(input);
      for i := 0 to high(Request.Unicodes) do
        set_add(s, Request.Unicodes[i]);
      s := input_glyph_set(input);
      set_add(s, 0); // .notdef is always part of a TrueType font
      for i := 0 to high(Request.Glyphs) do
        set_add(s, Request.Glyphs[i]);
      input_set_flags(input, HbSubsetFlags or HB_SUBSET_FLAGS_RETAIN_GIDS);
      if HbSubsetDropLayoutTables then
      begin
        s := input_set(input, HB_SUBSET_SETS_DROP_TABLE_TAG);
        set_add(s, HB_TAG_GSUB);
        set_add(s, HB_TAG_GPOS);
        set_add(s, HB_TAG_GDEF);
      end;
      subface := subset_or_fail(face_, input);
      if subface = nil then
        exit;
      subblob := face_reference_blob(subface);
      try
        len := 0;
        data := blob_get_data(subblob, len);
        // HarfBuzz < 10.0 returns an sfnt without tables instead of nil for a
        // face without glyphs: no table means failure, so the face goes whole
        if (data = nil) or
           (len < 12) or
           (((ord(data[4]) shl 8) or ord(data[5])) = 0) then
          exit;
        FastSetRawByteString(Output, data, len);
        result := true;
      finally
        blob_destroy(subblob);
      end;
    finally
      if subface <> nil then
        face_destroy(subface);
      if input <> nil then
        input_destroy(input);
      face_destroy(face_);
      blob_destroy(blob);
    end;
  end;
end;


var
  // what this unit registered, so that only its own services are released
  RegisteredShaper: IFontShaper;
  RegisteredSubsetter: IFontSubsetter;

procedure RegisterHarfBuzz;
begin
  if LoadHarfBuzz then
  begin
    RegisteredShaper := THarfBuzzShaper.Create;
    FontShaper := RegisteredShaper;
  end;
  if LoadHarfBuzzSubset then
  begin
    RegisteredSubsetter := THarfBuzzSubsetter.Create;
    FontSubsetter := RegisteredSubsetter;
  end;
end;

procedure UnregisterHarfBuzz;
begin
  // release the services before the libraries they call
  if FontShaper = RegisteredShaper then
    FontShaper := nil;
  if FontSubsetter = RegisteredSubsetter then
    FontSubsetter := nil;
  RegisteredShaper := nil;
  RegisteredSubsetter := nil;
  FreeAndNil(HarfBuzz); // calls FreeLib
  UnloadHarfBuzzSubset;
end;


initialization
  RegisterHarfBuzz;

finalization
  UnregisterHarfBuzz;

{$endif OSWINDOWS}

end.
