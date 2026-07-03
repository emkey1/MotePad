//==============================================================================
// MotePad - a native aarch64 (Apple Silicon) port of TinyRetroPad for macOS.
//
// Written in ARM64 assembly. Drives AppKit/Cocoa through the Objective-C runtime
// (objc_getClass / sel_registerName / objc_msgSend) and creates its controller /
// delegate class at runtime with class_addMethod, using assembly functions as the
// method implementations (IMPs).
//
// Build:  ./build.sh   (assembles + links -framework Cocoa, packages MotePad.app)
//
// Apple arm64 ABI notes that matter here:
//   * objc_msgSend(recv, SEL, args...) -> recv in x0, SEL in x1, args in x2.. / v0..
//   * A struct of 4 doubles (NSRect) is passed/returned in v0-v3 (HFA); NSSize in
//     v0-v1. Integer args continue in x2,x3,...
//   * v0-v7 are volatile: set float args immediately before the call that uses
//     them (an intervening msgSend can clobber them).
//   * Variadic args (NSLog, stringWithFormat:) go on the STACK, not in registers.
//==============================================================================

//==============================================================================
// Macros
//==============================================================================

// reg = &sym
.macro LEA reg, sym
    adrp \reg, \sym@PAGE
    add  \reg, \reg, \sym@PAGEOFF
.endm

// reg = *(uint64*)&sym   (load a cached class/selector pointer)
.macro LDG reg, sym
    adrp \reg, \sym@PAGE
    ldr  \reg, [\reg, \sym@PAGEOFF]
.endm

// reg = value of an external NSString* const (e.g. NSForegroundColorAttributeName)
.macro EXTNSSTR reg, sym
    adrp \reg, \sym@GOTPAGE
    ldr  \reg, [\reg, \sym@GOTPAGEOFF]
    ldr  \reg, [\reg]
.endm

// reg = pointer to an inline, whitespace-free C string (selector/class/type name)
.macro CSTR reg, str:req
    .pushsection __TEXT,__cstring
Lcstr_\@:
    .asciz "\str"
    .popsection
    LEA \reg, Lcstr_\@
.endm

// x1 = cached selector \sym, then objc_msgSend (x0 = recv and x2.. must be preset)
.macro CALL sym
    LDG x1, \sym
    bl   _objc_msgSend
.endm

// Declare a cached selector slot + a (slot,name) descriptor resolved at startup.
.macro DEFSEL sym, name
    .pushsection __DATA,__bss
    .p2align 3
\sym:
    .quad 0
    .popsection
    .pushsection __TEXT,__cstring
Lseln_\sym:
    .asciz "\name"
    .popsection
    .pushsection __DATA,__mpseldsc
    .quad \sym
    .quad Lseln_\sym
    .popsection
.endm

// Declare a cached class slot + a (slot,name) descriptor resolved at startup.
.macro DEFCLS sym, name
    .pushsection __DATA,__bss
    .p2align 3
\sym:
    .quad 0
    .popsection
    .pushsection __TEXT,__cstring
Lclsn_\sym:
    .asciz "\name"
    .popsection
    .pushsection __DATA,__mpclsdsc
    .quad \sym
    .quad Lclsn_\sym
    .popsection
.endm

// class_addMethod(cls, sel, imp, types)
.macro ADDMETHOD cls, selSym, impLbl, types
    mov  x0, \cls
    LDG  x1, \selSym
    LEA  x2, \impLbl
    CSTR x3, \types
    bl   _class_addMethod
.endm

// Add a leaf menu item (standard first-responder action, target = nil).
//   _add_item(menu=x0, titleCStr=x1, keyCStr=x2, actionSEL=x3, mask=w4, target=x5)
.macro ADDSTD menu, titleLbl, keyLbl, actionSym, mask
    mov  x0, \menu
    LEA  x1, \titleLbl
    LEA  x2, \keyLbl
    LDG  x3, \actionSym
    mov  w4, \mask
    mov  x5, #0
    bl   _add_item
.endm

// Add a leaf menu item targeting the MPController instance.
.macro ADDCTL menu, titleLbl, keyLbl, actionSym, mask
    mov  x0, \menu
    LEA  x1, \titleLbl
    LEA  x2, \keyLbl
    LDG  x3, \actionSym
    mov  w4, \mask
    LDG  x5, gController
    bl   _add_item
.endm

// Append a separator to a menu (menu in \menu).
.macro SEP menu
    LDG  x0, cls_NSMenuItem
    CALL sel_separatorItem
    mov  x2, x0
    mov  x0, \menu
    CALL sel_addItem
.endm

// Set .tag on the menu item currently in x0 (used after ADDSTD for find actions).
.macro SETTAG n
    mov  x2, #\n
    LDG  x1, sel_setTag
    bl   _objc_msgSend
.endm

// NSEventModifierFlags
.set MOD_SHIFT, 0x20000
.set MOD_CTRL,  0x40000
.set MOD_OPT,   0x80000
.set MOD_CMD,   0x100000

//==============================================================================
// Descriptor table boundaries (filled by DEFSEL/DEFCLS below, walked at startup)
//==============================================================================
    .section __DATA,__mpseldsc
    .p2align 3
mpsel_start:
    .section __DATA,__mpclsdsc
    .p2align 3
mpcls_start:
    .text

//==============================================================================
// Cached classes
//==============================================================================
    DEFCLS cls_NSApplication,     "NSApplication"
    DEFCLS cls_NSAutoreleasePool, "NSAutoreleasePool"
    DEFCLS cls_NSString,          "NSString"
    DEFCLS cls_NSWindow,          "NSWindow"
    DEFCLS cls_NSScrollView,      "NSScrollView"
    DEFCLS cls_NSTextView,        "NSTextView"
    DEFCLS cls_NSFont,            "NSFont"
    DEFCLS cls_NSFontManager,     "NSFontManager"
    DEFCLS cls_NSMenu,            "NSMenu"
    DEFCLS cls_NSMenuItem,        "NSMenuItem"
    DEFCLS cls_NSObject,          "NSObject"
    DEFCLS cls_NSOpenPanel,       "NSOpenPanel"
    DEFCLS cls_NSSavePanel,       "NSSavePanel"
    DEFCLS cls_NSAlert,           "NSAlert"
    DEFCLS cls_NSURL,             "NSURL"
    DEFCLS cls_NSView,            "NSView"
    DEFCLS cls_NSTextField,       "NSTextField"
    DEFCLS cls_NSBox,             "NSBox"
    DEFCLS cls_NSDate,            "NSDate"
    DEFCLS cls_NSDateFormatter,   "NSDateFormatter"
    DEFCLS cls_NSRulerView,       "NSRulerView"
    DEFCLS cls_NSArray,           "NSArray"
    DEFCLS cls_NSButton,          "NSButton"
    DEFCLS cls_NSColor,           "NSColor"
    DEFCLS cls_NSMutableDictionary,"NSMutableDictionary"

//==============================================================================
// Cached selectors
//==============================================================================
    // object / app lifecycle
    DEFSEL sel_alloc,             "alloc"
    DEFSEL sel_init,              "init"
    DEFSEL sel_initWithTitle,     "initWithTitle:"
    DEFSEL sel_initWithFrame,     "initWithFrame:"
    DEFSEL sel_sharedApplication, "sharedApplication"
    DEFSEL sel_setActivationPolicy,"setActivationPolicy:"
    DEFSEL sel_setDelegate,       "setDelegate:"
    DEFSEL sel_setMainMenu,       "setMainMenu:"
    DEFSEL sel_activateIgnoring,  "activateIgnoringOtherApps:"
    DEFSEL sel_run,               "run"
    DEFSEL sel_sharedFontManager, "sharedFontManager"
    DEFSEL sel_orderFrontFontPanel,"orderFrontFontPanel:"
    // window
    DEFSEL sel_initWithContentRect,"initWithContentRect:styleMask:backing:defer:"
    DEFSEL sel_setReleasedWhenClosed,"setReleasedWhenClosed:"
    DEFSEL sel_setTitle,          "setTitle:"
    DEFSEL sel_center,            "center"
    DEFSEL sel_makeKeyAndFront,   "makeKeyAndOrderFront:"
    DEFSEL sel_setContentView,    "setContentView:"
    DEFSEL sel_makeFirstResponder,"makeFirstResponder:"
    // scroll view
    DEFSEL sel_setHasVertScroller,"setHasVerticalScroller:"
    DEFSEL sel_setHasHorizScroller,"setHasHorizontalScroller:"
    DEFSEL sel_setBorderType,     "setBorderType:"
    DEFSEL sel_setDocumentView,   "setDocumentView:"
    DEFSEL sel_setAutoresizingMask,"setAutoresizingMask:"
    // text view
    DEFSEL sel_setString,         "setString:"
    DEFSEL sel_string,            "string"
    DEFSEL sel_setFont,           "setFont:"
    DEFSEL sel_setRichText,       "setRichText:"
    DEFSEL sel_setAllowsUndo,     "setAllowsUndo:"
    DEFSEL sel_setUsesFindBar,    "setUsesFindBar:"
    DEFSEL sel_setVertResizable,  "setVerticallyResizable:"
    DEFSEL sel_setHorizResizable, "setHorizontallyResizable:"
    DEFSEL sel_setMinSize,        "setMinSize:"
    DEFSEL sel_setMaxSize,        "setMaxSize:"
    DEFSEL sel_textContainer,     "textContainer"
    DEFSEL sel_setContainerSize,  "setContainerSize:"
    DEFSEL sel_setWidthTracks,    "setWidthTracksTextView:"
    DEFSEL sel_fontWithNameSize,  "fontWithName:size:"
    // menu
    DEFSEL sel_addItem,           "addItem:"
    DEFSEL sel_addItemWTAK,       "addItemWithTitle:action:keyEquivalent:"
    DEFSEL sel_setSubmenu,        "setSubmenu:"
    DEFSEL sel_setKEMM,           "setKeyEquivalentModifierMask:"
    DEFSEL sel_setTarget,         "setTarget:"
    DEFSEL sel_setTag,            "setTag:"
    DEFSEL sel_separatorItem,     "separatorItem"
    // string
    DEFSEL sel_strWithUTF8,       "stringWithUTF8String:"
    // custom action selectors
    DEFSEL sel_newDoc,            "newDoc:"
    DEFSEL sel_openDoc,           "openDoc:"
    DEFSEL sel_saveDoc,           "saveDoc:"
    DEFSEL sel_saveAsDoc,         "saveAsDoc:"
    DEFSEL sel_gotoLine,          "gotoLine:"
    DEFSEL sel_insertDateTime,    "insertDateTime:"
    DEFSEL sel_toggleWordWrap,    "toggleWordWrap:"
    DEFSEL sel_toggleStatusBar,   "toggleStatusBar:"
    DEFSEL sel_toggleLineNumbers, "toggleLineNumbers:"
    DEFSEL sel_showHelp,          "showHelp:"
    // standard first-responder selectors
    DEFSEL sel_print,             "print:"
    DEFSEL sel_runPageLayout,     "runPageLayout:"
    DEFSEL sel_undo,              "undo:"
    DEFSEL sel_redo,              "redo:"
    DEFSEL sel_cut,               "cut:"
    DEFSEL sel_copy,              "copy:"
    DEFSEL sel_paste,             "paste:"
    DEFSEL sel_delete,            "delete:"
    DEFSEL sel_selectAll,         "selectAll:"
    DEFSEL sel_perfFinder,        "performTextFinderAction:"
    DEFSEL sel_terminate,         "terminate:"
    DEFSEL sel_hide,              "hide:"
    DEFSEL sel_orderFrontStdAbout,"orderFrontStandardAboutPanel:"
    DEFSEL sel_performClose,      "performClose:"
    // delegate selectors (added to MPController)
    DEFSEL sel_appTermLast,       "applicationShouldTerminateAfterLastWindowClosed:"
    // introspection (self-test)
    DEFSEL sel_title,             "title"
    DEFSEL sel_submenu,           "submenu"
    DEFSEL sel_numberOfItems,     "numberOfItems"
    DEFSEL sel_itemAtIndex,       "itemAtIndex:"
    DEFSEL sel_isSeparator,       "isSeparatorItem"
    DEFSEL sel_mainMenu,          "mainMenu"
    DEFSEL sel_UTF8String,        "UTF8String"
    // document ops
    DEFSEL sel_setDocEdited,      "setDocumentEdited:"
    DEFSEL sel_setRepURL,         "setRepresentedURL:"
    DEFSEL sel_lastPathComp,      "lastPathComponent"
    DEFSEL sel_writeToURL,        "writeToURL:atomically:encoding:error:"
    DEFSEL sel_strWithContentsURL,"stringWithContentsOfURL:encoding:error:"
    DEFSEL sel_openPanel,         "openPanel"
    DEFSEL sel_savePanel,         "savePanel"
    DEFSEL sel_runModal,          "runModal"
    DEFSEL sel_URL,               "URL"
    DEFSEL sel_setAllowsMultiple, "setAllowsMultipleSelection:"
    DEFSEL sel_setNameField,      "setNameFieldStringValue:"
    DEFSEL sel_setMessageText,    "setMessageText:"
    DEFSEL sel_setInformativeText,"setInformativeText:"
    DEFSEL sel_addButtonTitle,    "addButtonWithTitle:"
    DEFSEL sel_retain,            "retain"
    DEFSEL sel_release,           "release"
    DEFSEL sel_fileURLWithPath,   "fileURLWithPath:"
    // delegate callbacks
    DEFSEL sel_textDidChange,     "textDidChange:"
    DEFSEL sel_windowShouldClose, "windowShouldClose:"
    DEFSEL sel_appShouldTerminate,"applicationShouldTerminate:"
    DEFSEL sel_selChange,         "textViewDidChangeSelection:"
    DEFSEL sel_validateMenuItem,  "validateMenuItem:"
    // views / status bar
    DEFSEL sel_addSubview,        "addSubview:"
    DEFSEL sel_removeFromSuper,   "removeFromSuperview"
    DEFSEL sel_setFrame,          "setFrame:"
    DEFSEL sel_bounds,            "bounds"
    DEFSEL sel_contentSize,       "contentSize"
    DEFSEL sel_setEditable,       "setEditable:"
    DEFSEL sel_setBezeled,        "setBezeled:"
    DEFSEL sel_setDrawsBackground,"setDrawsBackground:"
    DEFSEL sel_setSelectable,     "setSelectable:"
    DEFSEL sel_setBoxType,        "setBoxType:"
    DEFSEL sel_setStringValue,    "setStringValue:"
    DEFSEL sel_systemFontOfSize,  "systemFontOfSize:"
    DEFSEL sel_setState,          "setState:"
    DEFSEL sel_action,            "action"
    // Ln/Col computation
    DEFSEL sel_selectedRange,     "selectedRange"
    DEFSEL sel_substringToIndex,  "substringToIndex:"
    DEFSEL sel_componentsSep,     "componentsSeparatedByString:"
    DEFSEL sel_count,             "count"
    DEFSEL sel_lineRangeForRange, "lineRangeForRange:"
    DEFSEL sel_stringWithFormat,  "stringWithFormat:"
    DEFSEL sel_setSelectedRange,  "setSelectedRange:"
    DEFSEL sel_stringValue,       "stringValue"
    // go to line
    DEFSEL sel_setAccessoryView,  "setAccessoryView:"
    DEFSEL sel_window,            "window"
    DEFSEL sel_setInitialFirstResponder,"setInitialFirstResponder:"
    DEFSEL sel_integerValue,      "integerValue"
    DEFSEL sel_length,            "length"
    DEFSEL sel_scrollRangeToVisible,"scrollRangeToVisible:"
    // insert date/time
    DEFSEL sel_date,              "date"
    DEFSEL sel_setDateStyle,      "setDateStyle:"
    DEFSEL sel_setTimeStyle,      "setTimeStyle:"
    DEFSEL sel_stringFromDate,    "stringFromDate:"
    DEFSEL sel_shouldChangeText,  "shouldChangeTextInRange:replacementString:"
    DEFSEL sel_textStorage,       "textStorage"
    DEFSEL sel_replaceChars,      "replaceCharactersInRange:withString:"
    DEFSEL sel_didChangeText,     "didChangeText"
    // drag & drop
    DEFSEL sel_registerForDragged,"registerForDraggedTypes:"
    DEFSEL sel_draggingEntered,   "draggingEntered:"
    DEFSEL sel_draggingUpdated,   "draggingUpdated:"
    DEFSEL sel_performDrag,       "performDragOperation:"
    DEFSEL sel_draggingPasteboard,"draggingPasteboard"
    DEFSEL sel_propertyListForType,"propertyListForType:"
    DEFSEL sel_objectAtIndex,     "objectAtIndex:"
    DEFSEL sel_arrayWithObject,   "arrayWithObject:"
    DEFSEL sel_openFile,          "application:openFile:"
    // line-number ruler
    DEFSEL sel_layoutManager,     "layoutManager"
    DEFSEL sel_textContainerOrigin,"textContainerOrigin"
    DEFSEL sel_visibleRect,       "visibleRect"
    DEFSEL sel_glyphRangeForRect, "glyphRangeForBoundingRect:inTextContainer:"
    DEFSEL sel_charIndexForGlyph, "characterIndexForGlyphAtIndex:"
    DEFSEL sel_lineFragRect,      "lineFragmentRectForGlyphAtIndex:effectiveRange:"
    DEFSEL sel_drawAtPoint,       "drawAtPoint:withAttributes:"
    DEFSEL sel_initWithScrollView,"initWithScrollView:orientation:"
    DEFSEL sel_setClientView,     "setClientView:"
    DEFSEL sel_setRuleThickness,  "setRuleThickness:"
    DEFSEL sel_setVerticalRulerView,"setVerticalRulerView:"
    DEFSEL sel_setHasVerticalRuler,"setHasVerticalRuler:"
    DEFSEL sel_setRulersVisible,  "setRulersVisible:"
    DEFSEL sel_drawHashMarks,     "drawHashMarksAndLabelsInRect:"
    DEFSEL sel_setNeedsDisplay,   "setNeedsDisplay:"
    DEFSEL sel_characterAtIndex,  "characterAtIndex:"
    // in-window menu bar
    DEFSEL sel_setBordered,       "setBordered:"
    DEFSEL sel_setAction,         "setAction:"
    DEFSEL sel_tag,               "tag"
    DEFSEL sel_popUpPositioning,  "popUpMenuPositioningItem:atLocation:inView:"
    DEFSEL sel_winMenu,           "winMenu:"
    DEFSEL sel_keyEquivalent,     "keyEquivalent"
    DEFSEL sel_keyEquivMask,      "keyEquivalentModifierMask"
    // ruler label attributes
    DEFSEL sel_dictionary,        "dictionary"
    DEFSEL sel_setObjectForKey,   "setObject:forKey:"
    DEFSEL sel_secondaryLabelColor,"secondaryLabelColor"

    // close descriptor tables
    .section __DATA,__mpseldsc
mpsel_end:
    .section __DATA,__mpclsdsc
mpcls_end:
    .text

//==============================================================================
// Read-only data
//==============================================================================
    .section __TEXT,__const
    .p2align 3
d_big:      .double 10000000.0

    .section __TEXT,__cstring
str_empty:      .asciz ""
str_untitled:   .asciz "Untitled"
str_appname:    .asciz "MotePad"
str_courier:    .asciz "Courier"
// submenu titles
mt_file:        .asciz "File"
mt_edit:        .asciz "Edit"
mt_format:      .asciz "Format"
mt_view:        .asciz "View"
mt_help:        .asciz "Help"
// app menu
mi_about:       .asciz "About MotePad"
mi_hide:        .asciz "Hide MotePad"
mi_quit:        .asciz "Quit MotePad"
// file menu
mi_new:         .asciz "New"
mi_open:        .asciz "Open…"
mi_save:        .asciz "Save"
mi_saveas:      .asciz "Save As…"
mi_pagesetup:   .asciz "Page Setup…"
mi_print:       .asciz "Print…"
mi_close:       .asciz "Close"
// edit menu
mi_undo:        .asciz "Undo"
mi_redo:        .asciz "Redo"
mi_cut:         .asciz "Cut"
mi_copy:        .asciz "Copy"
mi_paste:       .asciz "Paste"
mi_delete:      .asciz "Delete"
mi_selectall:   .asciz "Select All"
mi_find:        .asciz "Find…"
mi_findnext:    .asciz "Find Next"
mi_replace:     .asciz "Replace…"
mi_goto:        .asciz "Go To Line…"
mi_datetime:    .asciz "Insert Date and Time"
// format menu
mi_wordwrap:    .asciz "Word Wrap"
mi_showfonts:   .asciz "Show Fonts"
// view menu
mi_statusbar:   .asciz "Status Bar"
mi_linenumbers: .asciz "Line Numbers"
// help menu
mi_help:        .asciz "MotePad Help"
// unsaved-changes alert
msg_unsaved:      .asciz "Do you want to save the changes you made?"
msg_unsaved_info: .asciz "Your changes will be lost if you don't save them."
btn_save:         .asciz "Save"
btn_dontsave:     .asciz "Don't Save"
btn_cancel:       .asciz "Cancel"
// status bar
fmt_lncol:      .asciz "Ln %ld, Col %ld"
str_nl:         .asciz "\n"
status_init:    .asciz "Ln 1, Col 1"
// go to line dialog
msg_goto:       .asciz "Go to Line"
msg_goto_info:  .asciz "Enter a line number:"
btn_go:         .asciz "Go"
// help dialog
msg_help:       .asciz "MotePad"
msg_help_info:  .asciz "A native aarch64 (Apple Silicon) port of TinyRetroPad.\n\nFile: New (⌘N), Open (⌘O), Save (⌘S), Save As (⇧⌘S), Page Setup (⇧⌘P), Print (⌘P).\nEdit: Undo/Redo, Cut/Copy/Paste, Find (⌘F), Find Next (⌘G), Replace (⇧⌘F), Go to Line (⌘L), Insert Date and Time.\nFormat: Word Wrap, Show Fonts (⌘T).\nView: Status Bar, Line Numbers.\n\nDrop a text file on the app to open it."
btn_ok:         .asciz "OK"
// drag & drop / ruler
pbtype_files:   .asciz "NSFilenamesPboardType"
fmt_ld:         .asciz "%ld"
enc_ruler:      .asciz "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"
ln_sample:      .asciz "line one\nline two\nline three\nline four\nline five\n"
// self-test dump headers
d_hdr_win:      .asciz "== window title =="
d_hdr_menu:     .asciz "== menu bar =="
d_hdr_winbar:   .asciz "== in-window menu bar =="
d_sep_top:      .asciz "----"
d_sep_item:     .asciz "  (separator)"
fmt_item:       .asciz "%@\tkey='%@' mask=0x%lx"
d_hdr_io:       .asciz "== io roundtrip =="
iopath:         .asciz "/private/tmp/motepad_selftest.txt"
iosample:       .asciz "hello from MotePad IO roundtrip\nline two"
d_hdr_lncol:    .asciz "== ln/col (expect Ln 2, Col 5) =="
lncol_sample:   .asciz "abc\ndefgh\nij"
d_hdr_goto:     .asciz "== goto line 3 (expect Ln 3, Col 1) =="
goto_sample:    .asciz "L1\nL2\nL3\nL4"
d_hdr_date:     .asciz "== date sample =="
// key equivalents
k_n: .asciz "n"
k_o: .asciz "o"
k_s: .asciz "s"
k_p: .asciz "p"
k_w: .asciz "w"
k_f: .asciz "f"
k_g: .asciz "g"
k_l: .asciz "l"
k_t: .asciz "t"
k_z: .asciz "z"
k_x: .asciz "x"
k_c: .asciz "c"
k_v: .asciz "v"
k_a: .asciz "a"
k_h: .asciz "h"
k_q: .asciz "q"
k_d: .asciz "d"
k_qmark: .asciz "?"

//==============================================================================
// Mutable state
//==============================================================================
    .section __DATA,__data
    .p2align 3
gApp:           .quad 0
gWindow:        .quad 0
gScroll:        .quad 0
gTextView:      .quad 0
gController:    .quad 0
gContentView:   .quad 0
gStatusView:    .quad 0
gStatusField:   .quad 0
gRuler:         .quad 0
gTVClass:       .quad 0
gWinBar:        .quad 0
gWinMenus:      .quad 0, 0, 0, 0, 0
gRulerAttrs:    .quad 0
gFileURL:       .quad 0
gDirty:         .byte 0
gWrap:          .byte 1
gStatusVisible: .byte 0
gLineNumbers:   .byte 0

//==============================================================================
// Code
//==============================================================================
    .section __TEXT,__text
    .p2align 2
    .globl _main

//------------------------------------------------------------------------------
// _main: program entry
//------------------------------------------------------------------------------
_main:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    // Resolve all cached selectors and classes first.
    bl   _resolve_runtime

    // Root autorelease pool (lives for the process lifetime).
    LDG  x0, cls_NSAutoreleasePool
    CALL sel_alloc
    CALL sel_init

    // app = [NSApplication sharedApplication]
    LDG  x0, cls_NSApplication
    CALL sel_sharedApplication
    LEA  x9, gApp
    str  x0, [x9]

    // [app setActivationPolicy:NSApplicationActivationPolicyRegular(0)]
    LDG  x0, gApp
    mov  x2, #0
    CALL sel_setActivationPolicy

    // Build controller + custom view classes; set controller as app delegate.
    bl   _make_controller
    bl   _make_textview_class
    LDG  x0, gApp
    LDG  x2, gController
    CALL sel_setDelegate

    // Build UI + menu.
    bl   _build_window
    bl   _build_menu

    // Self-test: if MOTEPAD_SELFTEST is set, dump menu/state and exit (no run loop).
    CSTR x0, MOTEPAD_SELFTEST
    bl   _getenv
    cbz  x0, Lnormrun
    bl   _selftest_dump
    mov  w0, #0
    ldp  x29, x30, [sp], #16
    ret
Lnormrun:

    // Optional: start with line numbers on + sample text (exercises the ruler
    // draw path under the real run loop). Enabled with MOTEPAD_LINENUMS=1.
    CSTR x0, MOTEPAD_LINENUMS
    bl   _getenv
    cbz  x0, Lnoln
    LEA  x9, gLineNumbers
    mov  w8, #1
    strb w8, [x9]
    LDG  x0, gScroll
    LDG  x1, sel_setRulersVisible
    mov  w2, #1
    bl   _objc_msgSend
    LEA  x0, ln_sample
    bl   _nsstr
    mov  x2, x0
    LDG  x0, gTextView
    CALL sel_setString
Lnoln:

    // [app activateIgnoringOtherApps:YES]
    LDG  x0, gApp
    mov  w2, #1
    CALL sel_activateIgnoring

    // [app run]
    LDG  x0, gApp
    CALL sel_run

    mov  w0, #0
    ldp  x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _resolve_runtime: walk descriptor tables, fill cached class/selector slots
//------------------------------------------------------------------------------
    .p2align 2
_resolve_runtime:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]

    // selectors
    LEA  x19, mpsel_start
    LEA  x20, mpsel_end
1:  cmp  x19, x20
    b.hs 2f
    ldr  x0, [x19, #8]          // name
    bl   _sel_registerName
    ldr  x9, [x19]             // slot
    str  x0, [x9]
    add  x19, x19, #16
    b    1b

2:  // classes
    LEA  x19, mpcls_start
    LEA  x20, mpcls_end
3:  cmp  x19, x20
    b.hs 4f
    ldr  x0, [x19, #8]
    bl   _objc_getClass
    ldr  x9, [x19]
    str  x0, [x9]
    add  x19, x19, #16
    b    3b

4:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

//------------------------------------------------------------------------------
// _nsstr: x0 = C string ptr  ->  x0 = NSString*
//------------------------------------------------------------------------------
    .p2align 2
_nsstr:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    mov  x2, x0
    LDG  x0, cls_NSString
    LDG  x1, sel_strWithUTF8
    bl   _objc_msgSend
    ldp  x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _make_controller: create the MPController class, add methods, instantiate.
//------------------------------------------------------------------------------
    .p2align 2
_make_controller:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]

    // cls = objc_allocateClassPair(NSObject, "MPController", 0)
    LDG  x0, cls_NSObject
    CSTR x1, MPController
    mov  x2, #0
    bl   _objc_allocateClassPair
    mov  x19, x0

    ADDMETHOD x19, sel_appTermLast,       _imp_appTermLast,     c@:@
    ADDMETHOD x19, sel_newDoc,            _imp_newDoc,          v@:@
    ADDMETHOD x19, sel_openDoc,           _imp_openDoc,         v@:@
    ADDMETHOD x19, sel_saveDoc,           _imp_saveDoc,         v@:@
    ADDMETHOD x19, sel_saveAsDoc,         _imp_saveAsDoc,       v@:@
    ADDMETHOD x19, sel_gotoLine,          _imp_gotoLine,        v@:@
    ADDMETHOD x19, sel_insertDateTime,    _imp_insertDateTime,  v@:@
    ADDMETHOD x19, sel_toggleWordWrap,    _imp_toggleWordWrap,  v@:@
    ADDMETHOD x19, sel_toggleStatusBar,   _imp_toggleStatusBar, v@:@
    ADDMETHOD x19, sel_toggleLineNumbers, _imp_toggleLineNumbers, v@:@
    ADDMETHOD x19, sel_showHelp,          _imp_showHelp,        v@:@
    ADDMETHOD x19, sel_textDidChange,     _imp_textDidChange,     v@:@
    ADDMETHOD x19, sel_windowShouldClose, _imp_windowShouldClose, c@:@
    ADDMETHOD x19, sel_appShouldTerminate,_imp_appShouldTerminate, Q@:@
    ADDMETHOD x19, sel_selChange,         _imp_selChange,         v@:@
    ADDMETHOD x19, sel_validateMenuItem,  _imp_validateMenuItem,  c@:@
    ADDMETHOD x19, sel_openFile,          _imp_openFile,          c@:@@
    ADDMETHOD x19, sel_winMenu,           _imp_winMenu,           v@:@

    mov  x0, x19
    bl   _objc_registerClassPair

    // controller = [[MPController alloc] init]
    mov  x0, x19
    CALL sel_alloc
    CALL sel_init
    LEA  x9, gController
    str  x0, [x9]

    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _make_textview_class: MPTextView : NSTextView with file-drop handling.
_make_textview_class:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    LDG  x0, cls_NSTextView
    CSTR x1, MPTextView
    mov  x2, #0
    bl   _objc_allocateClassPair
    mov  x19, x0
    ADDMETHOD x19, sel_draggingEntered,   _imp_dragEntered, Q@:@
    ADDMETHOD x19, sel_draggingUpdated,   _imp_dragEntered, Q@:@
    ADDMETHOD x19, sel_performDrag,       _imp_performDrag, c@:@
    mov  x0, x19
    bl   _objc_registerClassPair
    LEA  x9, gTVClass
    str  x19, [x9]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _setup_ruler: create MPRuler : NSRulerView, attach to scroll (hidden by default).
_setup_ruler:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    // MPRuler class
    LDG  x0, cls_NSRulerView
    CSTR x1, MPRuler
    mov  x2, #0
    bl   _objc_allocateClassPair
    mov  x19, x0
    mov  x0, x19
    LDG  x1, sel_drawHashMarks
    LEA  x2, _imp_ruler_draw
    LEA  x3, enc_ruler
    bl   _class_addMethod
    mov  x0, x19
    bl   _objc_registerClassPair
    // ruler = [[MPRuler alloc] initWithScrollView:gScroll orientation:1]
    mov  x0, x19
    CALL sel_alloc
    mov  x20, x0
    mov  x0, x20
    LDG  x1, sel_initWithScrollView
    LDG  x2, gScroll
    mov  x3, #1                        // NSVerticalRuler
    bl   _objc_msgSend
    mov  x20, x0
    LEA  x9, gRuler
    str  x20, [x9]
    // clientView = textView
    mov  x0, x20
    LDG  x1, sel_setClientView
    LDG  x2, gTextView
    bl   _objc_msgSend
    // ruleThickness = 44
    mov  x0, x20
    LDG  x1, sel_setRuleThickness
    mov  w9, #44
    scvtf d0, w9
    bl   _objc_msgSend
    // attach to scroll, hidden for now
    LDG  x0, gScroll
    LDG  x1, sel_setVerticalRulerView
    mov  x2, x20
    bl   _objc_msgSend
    LDG  x0, gScroll
    LDG  x1, sel_setHasVerticalRuler
    mov  w2, #1
    bl   _objc_msgSend
    LDG  x0, gScroll
    LDG  x1, sel_setRulersVisible
    mov  w2, #0
    bl   _objc_msgSend
    // Line-number label attributes: an adaptive color (visible in light + dark)
    // and a small font. Drawing with nil attributes defaults to black, which is
    // invisible on the dark ruler in dark mode.
    LDG  x0, cls_NSMutableDictionary
    CALL sel_dictionary
    mov  x19, x0                       // attrs dict (x19/x20 no longer needed here)
    LDG  x0, cls_NSColor
    CALL sel_secondaryLabelColor
    mov  x20, x0
    mov  x0, x19
    mov  x2, x20
    EXTNSSTR x3, _NSForegroundColorAttributeName
    LDG  x1, sel_setObjectForKey
    bl   _objc_msgSend
    LDG  x0, cls_NSFont
    LDG  x1, sel_systemFontOfSize
    mov  w9, #11
    scvtf d0, w9
    bl   _objc_msgSend
    mov  x20, x0
    mov  x0, x19
    mov  x2, x20
    EXTNSSTR x3, _NSFontAttributeName
    LDG  x1, sel_setObjectForKey
    bl   _objc_msgSend
    mov  x0, x19
    CALL sel_retain
    LEA  x9, gRulerAttrs
    str  x0, [x9]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _add_winbtn: add one menu-bar button. x0=bar x1=titleCStr x2=tag x3=xpos
_add_winbtn:
    stp  x29, x30, [sp, #-64]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    mov  x19, x0                       // bar
    mov  x20, x1                       // title cstr
    mov  x21, x2                       // tag
    mov  x22, x3                       // xpos
    LDG  x0, cls_NSButton
    CALL sel_alloc
    mov  x23, x0
    scvtf d0, x22                      // x
    mov  w9, #2
    scvtf d1, w9                       // y
    mov  w9, #66
    scvtf d2, w9                       // width
    mov  w9, #22
    scvtf d3, w9                       // height
    mov  x0, x23
    CALL sel_initWithFrame
    mov  x23, x0
    mov  x0, x20
    bl   _nsstr
    mov  x24, x0
    mov  x0, x23
    LDG  x1, sel_setTitle
    mov  x2, x24
    bl   _objc_msgSend
    mov  x0, x23
    LDG  x1, sel_setBordered
    mov  w2, #0
    bl   _objc_msgSend
    mov  x0, x23
    LDG  x1, sel_setTag
    mov  x2, x21
    bl   _objc_msgSend
    mov  x0, x23
    LDG  x1, sel_setTarget
    LDG  x2, gController
    bl   _objc_msgSend
    mov  x0, x23
    LDG  x1, sel_setAction
    LDG  x2, sel_winMenu
    bl   _objc_msgSend
    mov  x0, x19
    LDG  x1, sel_addSubview
    mov  x2, x23
    bl   _objc_msgSend
    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x29, x30, [sp], #64
    ret

// Populate a window-bar menu (x0 = NSMenu) with the same commands as the global
// menu bar, but with no key equivalents (the global bar owns the shortcuts).
    .p2align 2
_fill_win_file:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    ADDCTL x19, mi_new,    k_n, sel_newDoc,    #-1
    ADDCTL x19, mi_open,   k_o, sel_openDoc,   #-1
    ADDCTL x19, mi_save,   k_s, sel_saveDoc,   #-1
    ADDCTL x19, mi_saveas, k_s, sel_saveAsDoc, (MOD_CMD|MOD_SHIFT)
    SEP  x19
    ADDSTD x19, mi_pagesetup, k_p, sel_runPageLayout, (MOD_CMD|MOD_SHIFT)
    ADDSTD x19, mi_print,     k_p, sel_print,        #-1
    SEP  x19
    ADDSTD x19, mi_close, k_w, sel_performClose, #-1
    ADDSTD x19, mi_quit,  k_q, sel_terminate,    #-1
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
_fill_win_edit:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    ADDSTD x19, mi_undo, k_z, sel_undo, #-1
    ADDSTD x19, mi_redo, k_z, sel_redo, (MOD_CMD|MOD_SHIFT)
    SEP  x19
    ADDSTD x19, mi_cut,       k_x, sel_cut,       #-1
    ADDSTD x19, mi_copy,      k_c, sel_copy,      #-1
    ADDSTD x19, mi_paste,     k_v, sel_paste,     #-1
    ADDSTD x19, mi_delete,    str_empty, sel_delete, #-1
    ADDSTD x19, mi_selectall, k_a, sel_selectAll, #-1
    SEP  x19
    ADDSTD x19, mi_find,     k_f, sel_perfFinder, #-1
    SETTAG 1
    ADDSTD x19, mi_findnext, k_g, sel_perfFinder, #-1
    SETTAG 2
    ADDSTD x19, mi_replace,  k_f, sel_perfFinder, (MOD_CMD|MOD_SHIFT)
    SETTAG 12
    ADDCTL x19, mi_goto,     k_l, sel_gotoLine,   #-1
    SEP  x19
    ADDCTL x19, mi_datetime, k_d, sel_insertDateTime, #-1
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
_fill_win_format:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    ADDCTL x19, mi_wordwrap, k_w, sel_toggleWordWrap, (MOD_CMD|MOD_OPT)
    // Show Fonts -> target = font manager
    LDG  x0, cls_NSFontManager
    CALL sel_sharedFontManager
    mov  x20, x0
    mov  x0, x19
    LEA  x1, mi_showfonts
    LEA  x2, k_t
    LDG  x3, sel_orderFrontFontPanel
    mov  w4, #-1
    mov  x5, x20
    bl   _add_item
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
_fill_win_view:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    ADDCTL x19, mi_statusbar,   k_s, sel_toggleStatusBar,   (MOD_CMD|MOD_OPT)
    ADDCTL x19, mi_linenumbers, k_l, sel_toggleLineNumbers, (MOD_CMD|MOD_OPT)
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
_fill_win_help:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    ADDCTL x19, mi_help, k_qmark, sel_showHelp, #-1
    SEP  x19
    ADDSTD x19, mi_about, str_empty, sel_orderFrontStdAbout, #-1
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _build_winbar: create the in-window menu bar (5 buttons + their menus).
_build_winbar:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    // bar view (placeholder frame; positioned by _relayout)
    LDG  x0, cls_NSView
    CALL sel_alloc
    mov  x19, x0
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #26
    scvtf d3, w9
    mov  x0, x19
    CALL sel_initWithFrame
    mov  x19, x0
    LEA  x9, gWinBar
    str  x19, [x9]
    mov  x0, x19
    LDG  x1, sel_setAutoresizingMask
    mov  w2, #10                       // width | flexible bottom margin (pin to top)
    bl   _objc_msgSend
    // bottom hairline
    LDG  x0, cls_NSBox
    CALL sel_alloc
    mov  x20, x0
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #1
    scvtf d3, w9
    mov  x0, x20
    CALL sel_initWithFrame
    mov  x20, x0
    mov  x0, x20
    LDG  x1, sel_setBoxType
    mov  w2, #2
    bl   _objc_msgSend
    mov  x0, x20
    LDG  x1, sel_setAutoresizingMask
    mov  w2, #2
    bl   _objc_msgSend
    mov  x0, x19
    LDG  x1, sel_addSubview
    mov  x2, x20
    bl   _objc_msgSend
    // File
    LDG  x0, cls_NSMenu
    CALL sel_alloc
    CALL sel_init
    mov  x20, x0
    LEA  x9, gWinMenus
    str  x20, [x9]
    mov  x0, x20
    bl   _fill_win_file
    mov  x0, x19
    LEA  x1, mt_file
    mov  x2, #0
    mov  x3, #6
    bl   _add_winbtn
    // Edit
    LDG  x0, cls_NSMenu
    CALL sel_alloc
    CALL sel_init
    mov  x20, x0
    LEA  x9, gWinMenus
    str  x20, [x9, #8]
    mov  x0, x20
    bl   _fill_win_edit
    mov  x0, x19
    LEA  x1, mt_edit
    mov  x2, #1
    mov  x3, #74
    bl   _add_winbtn
    // Format
    LDG  x0, cls_NSMenu
    CALL sel_alloc
    CALL sel_init
    mov  x20, x0
    LEA  x9, gWinMenus
    str  x20, [x9, #16]
    mov  x0, x20
    bl   _fill_win_format
    mov  x0, x19
    LEA  x1, mt_format
    mov  x2, #2
    mov  x3, #142
    bl   _add_winbtn
    // View
    LDG  x0, cls_NSMenu
    CALL sel_alloc
    CALL sel_init
    mov  x20, x0
    LEA  x9, gWinMenus
    str  x20, [x9, #24]
    mov  x0, x20
    bl   _fill_win_view
    mov  x0, x19
    LEA  x1, mt_view
    mov  x2, #3
    mov  x3, #210
    bl   _add_winbtn
    // Help
    LDG  x0, cls_NSMenu
    CALL sel_alloc
    CALL sel_init
    mov  x20, x0
    LEA  x9, gWinMenus
    str  x20, [x9, #32]
    mov  x0, x20
    bl   _fill_win_help
    mov  x0, x19
    LEA  x1, mt_help
    mov  x2, #4
    mov  x3, #278
    bl   _add_winbtn
    // attach bar to content view
    LDG  x0, gContentView
    LDG  x1, sel_addSubview
    mov  x2, x19
    bl   _objc_msgSend
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

//------------------------------------------------------------------------------
// _build_window: create window + scroll view + text view
//------------------------------------------------------------------------------
    .p2align 2
_build_window:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]

    // --- window ---
    LDG  x0, cls_NSWindow
    CALL sel_alloc
    mov  x19, x0
    // rect (0,0,800,640) in v0-v3 immediately before the init call
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #640
    scvtf d3, w9
    mov  x0, x19
    mov  w2, #15               // Titled|Closable|Miniaturizable|Resizable
    mov  w3, #2                // NSBackingStoreBuffered
    mov  w4, #0                // defer NO
    CALL sel_initWithContentRect
    mov  x19, x0
    LEA  x9, gWindow
    str  x19, [x9]
    // releasedWhenClosed NO (we keep a global ref)
    mov  x0, x19
    mov  w2, #0
    CALL sel_setReleasedWhenClosed
    // title "Untitled"
    LEA  x0, str_untitled
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_setTitle
    // window delegate = controller
    mov  x0, x19
    LDG  x2, gController
    CALL sel_setDelegate

    // --- scroll view ---
    LDG  x0, cls_NSScrollView
    CALL sel_alloc
    mov  x20, x0
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #640
    scvtf d3, w9
    mov  x0, x20
    CALL sel_initWithFrame
    mov  x20, x0
    LEA  x9, gScroll
    str  x20, [x9]
    mov  x0, x20
    mov  w2, #1
    CALL sel_setHasVertScroller
    mov  x0, x20
    mov  w2, #0
    CALL sel_setBorderType            // NSNoBorder
    mov  x0, x20
    mov  w2, #18                      // width|height sizable
    CALL sel_setAutoresizingMask

    // --- text view (MPTextView, accepts file drops) ---
    LDG  x0, gTVClass
    CALL sel_alloc
    mov  x21, x0
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #640
    scvtf d3, w9
    mov  x0, x21
    CALL sel_initWithFrame
    mov  x21, x0
    LEA  x9, gTextView
    str  x21, [x9]
    // register for file-URL drags: [tv registerForDraggedTypes:@[@"NSFilenamesPboardType"]]
    LEA  x0, pbtype_files
    bl   _nsstr
    mov  x2, x0
    LDG  x0, cls_NSArray
    LDG  x1, sel_arrayWithObject
    bl   _objc_msgSend
    mov  x2, x0
    mov  x0, x21
    LDG  x1, sel_registerForDragged
    bl   _objc_msgSend
    // plain-text (Notepad-like), undo, native find bar
    mov  x0, x21
    mov  w2, #0
    CALL sel_setRichText
    mov  x0, x21
    mov  w2, #1
    CALL sel_setAllowsUndo
    mov  x0, x21
    mov  w2, #1
    CALL sel_setUsesFindBar
    // resize behaviour for scroll view hosting
    mov  x0, x21
    mov  w2, #1
    CALL sel_setVertResizable
    mov  x0, x21
    mov  w2, #0
    CALL sel_setHorizResizable
    mov  x0, x21
    mov  w2, #2                       // width sizable
    CALL sel_setAutoresizingMask
    // minSize (0,640)
    fmov d0, xzr
    mov  w9, #640
    scvtf d1, w9
    mov  x0, x21
    CALL sel_setMinSize
    // maxSize (big,big)
    LEA  x9, d_big
    ldr  d0, [x9]
    ldr  d1, [x9]
    mov  x0, x21
    CALL sel_setMaxSize
    // text view delegate = controller
    mov  x0, x21
    LDG  x2, gController
    CALL sel_setDelegate
    // font Courier 13
    LEA  x0, str_courier
    bl   _nsstr
    mov  x22, x0
    LDG  x0, cls_NSFont
    mov  x2, x22
    mov  w9, #13
    scvtf d0, w9
    CALL sel_fontWithNameSize
    mov  x22, x0
    mov  x0, x21
    mov  x2, x22
    CALL sel_setFont
    // container widthTracks YES, size (800,big)
    mov  x0, x21
    CALL sel_textContainer
    mov  x22, x0
    mov  x0, x22
    mov  w2, #1
    CALL sel_setWidthTracks
    mov  w9, #800
    scvtf d0, w9
    LEA  x9, d_big
    ldr  d1, [x9]
    mov  x0, x22
    CALL sel_setContainerSize

    // --- assemble ---
    mov  x0, x20
    mov  x2, x21
    CALL sel_setDocumentView
    // container content view (holds scroll + optional status bar)
    LDG  x0, cls_NSView
    CALL sel_alloc
    mov  x22, x0
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #640
    scvtf d3, w9
    mov  x0, x22
    CALL sel_initWithFrame
    mov  x22, x0
    LEA  x9, gContentView
    str  x22, [x9]
    mov  x0, x19
    mov  x2, x22
    CALL sel_setContentView
    // container addSubview: scroll
    mov  x0, x22
    LDG  x1, sel_addSubview
    mov  x2, x20
    bl   _objc_msgSend
    // build status bar (created hidden)
    bl   _build_status
    // first responder + show
    mov  x0, x19
    mov  x2, x21
    CALL sel_makeFirstResponder
    mov  x0, x19
    CALL sel_center
    mov  x0, x19
    mov  x2, #0
    CALL sel_makeKeyAndFront
    // line-number ruler (created hidden)
    bl   _setup_ruler
    // in-window menu bar, then lay everything out
    bl   _build_winbar
    bl   _relayout

    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

//------------------------------------------------------------------------------
// _add_item: add a leaf menu item.
//   x0=menu x1=titleCStr x2=keyCStr x3=actionSEL w4=mask(-1 skip) x5=target(0 skip)
//   returns x0 = NSMenuItem
//------------------------------------------------------------------------------
    .p2align 2
_add_item:
    stp  x29, x30, [sp, #-80]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]
    mov  x19, x0                // menu
    mov  x20, x2                // keyCStr (save before nsstr clobbers)
    mov  x21, x3                // action
    mov  w22, w4                // mask
    mov  x23, x5                // target
    // title = nsstr(x1)
    mov  x0, x1
    bl   _nsstr
    mov  x24, x0
    // key = nsstr(keyCStr)
    mov  x0, x20
    bl   _nsstr
    mov  x25, x0
    // item = [menu addItemWithTitle:title action:action keyEquivalent:key]
    mov  x0, x19
    LDG  x1, sel_addItemWTAK
    mov  x2, x24
    mov  x3, x21
    mov  x4, x25
    bl   _objc_msgSend
    mov  x19, x0                // reuse x19 for item
    // set modifier mask?
    cmn  w22, #1
    b.eq 1f
    mov  x0, x19
    LDG  x1, sel_setKEMM
    mov  w2, w22
    bl   _objc_msgSend
1:  // set target?
    cbz  x23, 2f
    mov  x0, x19
    LDG  x1, sel_setTarget
    mov  x2, x23
    bl   _objc_msgSend
2:  mov  x0, x19
    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x25, x26, [sp, #64]
    ldp  x29, x30, [sp], #80
    ret

//------------------------------------------------------------------------------
// _add_submenu: x0=mainMenu x1=titleCStr -> x0 = new submenu (NSMenu)
//------------------------------------------------------------------------------
    .p2align 2
_add_submenu:
    stp  x29, x30, [sp, #-64]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    mov  x19, x0                // mainMenu
    mov  x20, x1                // titleCStr
    // title NSString
    mov  x0, x20
    bl   _nsstr
    mov  x21, x0
    // submenu = [[NSMenu alloc] initWithTitle:title]
    LDG  x0, cls_NSMenu
    CALL sel_alloc
    mov  x2, x21
    CALL sel_initWithTitle
    mov  x22, x0
    // parent = [[NSMenuItem alloc] init]
    LDG  x0, cls_NSMenuItem
    CALL sel_alloc
    CALL sel_init
    mov  x23, x0
    // [parent setSubmenu:submenu]
    mov  x0, x23
    mov  x2, x22
    CALL sel_setSubmenu
    // [mainMenu addItem:parent]
    mov  x0, x19
    mov  x2, x23
    CALL sel_addItem
    mov  x0, x22                // return submenu
    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x29, x30, [sp], #64
    ret

//------------------------------------------------------------------------------
// _build_menu: construct the global menu bar
//------------------------------------------------------------------------------
    .p2align 2
_build_menu:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]

    // mainMenu = [[NSMenu alloc] init]
    LDG  x0, cls_NSMenu
    CALL sel_alloc
    CALL sel_init
    mov  x19, x0

    // fontManager (Show Fonts target)
    LDG  x0, cls_NSFontManager
    CALL sel_sharedFontManager
    mov  x21, x0

    // ---- App menu ----
    mov  x0, x19
    LEA  x1, str_appname
    bl   _add_submenu
    mov  x20, x0
    ADDSTD x20, mi_about, str_empty, sel_orderFrontStdAbout, #-1
    SEP  x20
    ADDSTD x20, mi_hide,  k_h, sel_hide,      #-1
    ADDSTD x20, mi_quit,  k_q, sel_terminate, #-1

    // ---- File menu ----
    mov  x0, x19
    LEA  x1, mt_file
    bl   _add_submenu
    mov  x20, x0
    ADDCTL x20, mi_new,    k_n, sel_newDoc,    #-1
    ADDCTL x20, mi_open,   k_o, sel_openDoc,   #-1
    ADDCTL x20, mi_save,   k_s, sel_saveDoc,   #-1
    ADDCTL x20, mi_saveas, k_s, sel_saveAsDoc, (MOD_CMD|MOD_SHIFT)
    SEP  x20
    ADDSTD x20, mi_pagesetup, k_p, sel_runPageLayout, (MOD_CMD|MOD_SHIFT)
    ADDSTD x20, mi_print,     k_p, sel_print,        #-1
    SEP  x20
    ADDSTD x20, mi_close,     k_w, sel_performClose, #-1

    // ---- Edit menu ----
    mov  x0, x19
    LEA  x1, mt_edit
    bl   _add_submenu
    mov  x20, x0
    ADDSTD x20, mi_undo, k_z, sel_undo, #-1
    ADDSTD x20, mi_redo, k_z, sel_redo, (MOD_CMD|MOD_SHIFT)
    SEP  x20
    ADDSTD x20, mi_cut,       k_x, sel_cut,       #-1
    ADDSTD x20, mi_copy,      k_c, sel_copy,      #-1
    ADDSTD x20, mi_paste,     k_v, sel_paste,     #-1
    ADDSTD x20, mi_delete,    str_empty, sel_delete, #-1
    ADDSTD x20, mi_selectall, k_a, sel_selectAll, #-1
    SEP  x20
    ADDSTD x20, mi_find,     k_f, sel_perfFinder, #-1
    SETTAG 1
    ADDSTD x20, mi_findnext, k_g, sel_perfFinder, #-1
    SETTAG 2
    ADDSTD x20, mi_replace,  k_f, sel_perfFinder, (MOD_CMD|MOD_SHIFT)
    SETTAG 12
    ADDCTL x20, mi_goto,     k_l, sel_gotoLine,   #-1
    SEP  x20
    ADDCTL x20, mi_datetime, k_d, sel_insertDateTime, #-1

    // ---- Format menu ----
    mov  x0, x19
    LEA  x1, mt_format
    bl   _add_submenu
    mov  x20, x0
    ADDCTL x20, mi_wordwrap, k_w, sel_toggleWordWrap, (MOD_CMD|MOD_OPT)
    // Show Fonts -> target = fontManager
    mov  x0, x20
    LEA  x1, mi_showfonts
    LEA  x2, k_t
    LDG  x3, sel_orderFrontFontPanel
    mov  w4, #-1
    mov  x5, x21
    bl   _add_item

    // ---- View menu ----
    mov  x0, x19
    LEA  x1, mt_view
    bl   _add_submenu
    mov  x20, x0
    ADDCTL x20, mi_statusbar,   k_s, sel_toggleStatusBar,   (MOD_CMD|MOD_OPT)
    ADDCTL x20, mi_linenumbers, k_l, sel_toggleLineNumbers, (MOD_CMD|MOD_OPT)

    // ---- Help menu ----
    mov  x0, x19
    LEA  x1, mt_help
    bl   _add_submenu
    mov  x20, x0
    ADDCTL x20, mi_help, k_qmark, sel_showHelp, #-1

    // [app setMainMenu:mainMenu]
    LDG  x0, gApp
    mov  x2, x19
    CALL sel_setMainMenu

    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

//------------------------------------------------------------------------------
// _puts_nsstr: x0 = NSString*  ->  puts([s UTF8String])
//------------------------------------------------------------------------------
    .p2align 2
_puts_nsstr:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    LDG  x1, sel_UTF8String
    bl   _objc_msgSend
    cbz  x0, 1f
    bl   _puts
1:  ldp  x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _puts_item: print "title  key='k' mask=0x..." for a menu item (self-test only)
//------------------------------------------------------------------------------
    .p2align 2
_puts_item:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    mov  x19, x0
    mov  x0, x19
    LDG  x1, sel_title
    bl   _objc_msgSend
    mov  x20, x0
    mov  x0, x19
    LDG  x1, sel_keyEquivalent
    bl   _objc_msgSend
    mov  x21, x0
    mov  x0, x19
    LDG  x1, sel_keyEquivMask
    bl   _objc_msgSend
    mov  x22, x0
    LEA  x0, fmt_item
    bl   _nsstr
    mov  x2, x0
    LDG  x0, cls_NSString
    LDG  x1, sel_stringWithFormat
    sub  sp, sp, #32
    str  x20, [sp]
    str  x21, [sp, #8]
    str  x22, [sp, #16]
    bl   _objc_msgSend
    add  sp, sp, #32
    bl   _puts_nsstr
    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

//------------------------------------------------------------------------------
// _selftest_dump: introspect the live window + menu bar and print to stdout.
//------------------------------------------------------------------------------
    .p2align 2
_selftest_dump:
    stp  x29, x30, [sp, #-80]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]

    // window title
    LEA  x0, d_hdr_win
    bl   _puts
    LDG  x0, gWindow
    CALL sel_title
    bl   _puts_nsstr

    // menu bar
    LEA  x0, d_hdr_menu
    bl   _puts
    LDG  x0, gApp
    CALL sel_mainMenu
    mov  x19, x0                       // mainMenu
    mov  x0, x19
    CALL sel_numberOfItems
    mov  x20, x0                       // top count
    mov  x21, #0                       // i
Ltop:
    cmp  x21, x20
    b.ge Ldumpdone
    mov  x0, x19
    mov  x2, x21
    CALL sel_itemAtIndex
    mov  x22, x0                       // top item
    LEA  x0, d_sep_top
    bl   _puts
    // submenu?
    mov  x0, x22
    CALL sel_submenu
    mov  x25, x0
    cbz  x25, LnextTop
    // print submenu title
    mov  x0, x25
    CALL sel_title
    bl   _puts_nsstr
    // iterate submenu items
    mov  x0, x25
    CALL sel_numberOfItems
    mov  x23, x0
    mov  x24, #0
Litem:
    cmp  x24, x23
    b.ge LnextTop
    mov  x0, x25
    mov  x2, x24
    CALL sel_itemAtIndex
    mov  x26, x0
    mov  x0, x26
    CALL sel_isSeparator
    and  x0, x0, #0xff
    cbz  x0, LnotSep
    LEA  x0, d_sep_item
    bl   _puts
    b    LitemNext
LnotSep:
    mov  x0, x26
    bl   _puts_item
LitemNext:
    add  x24, x24, #1
    b    Litem
LnextTop:
    add  x21, x21, #1
    b    Ltop
Ldumpdone:
    // ---- in-window menu bar (walk the 5 popup menus) ----
    LEA  x0, d_hdr_winbar
    bl   _puts
    mov  x21, #0                       // menu index
Lwmenu:
    cmp  x21, #5
    b.ge Lwmdone
    LEA  x9, gWinMenus
    ldr  x19, [x9, x21, lsl #3]
    LEA  x0, d_sep_top
    bl   _puts
    mov  x0, x19
    CALL sel_numberOfItems
    mov  x23, x0
    mov  x24, #0
Lwitem:
    cmp  x24, x23
    b.ge Lwnext
    mov  x0, x19
    mov  x2, x24
    CALL sel_itemAtIndex
    mov  x26, x0
    mov  x0, x26
    CALL sel_isSeparator
    and  x0, x0, #0xff
    cbz  x0, Lwnotsep
    LEA  x0, d_sep_item
    bl   _puts
    b    Lwinext
Lwnotsep:
    mov  x0, x26
    bl   _puts_item
Lwinext:
    add  x24, x24, #1
    b    Lwitem
Lwnext:
    add  x21, x21, #1
    b    Lwmenu
Lwmdone:

    // ---- document IO round trip (write sample, clear, read back, print) ----
    LEA  x0, d_hdr_io
    bl   _puts
    LEA  x0, iopath
    bl   _nsstr
    mov  x20, x0
    LDG  x0, cls_NSURL
    LDG  x1, sel_fileURLWithPath
    mov  x2, x20
    bl   _objc_msgSend
    mov  x19, x0                       // url
    LEA  x0, iosample
    bl   _nsstr
    mov  x2, x0
    LDG  x0, gTextView
    CALL sel_setString
    mov  x0, x19
    bl   _write_text_to_url
    LEA  x0, str_empty
    bl   _nsstr
    mov  x2, x0
    LDG  x0, gTextView
    CALL sel_setString
    mov  x0, x19
    bl   _read_url_to_text
    LDG  x0, gTextView
    CALL sel_string
    bl   _puts_nsstr

    // ---- Ln/Col computation test ----
    LEA  x0, d_hdr_lncol
    bl   _puts
    LEA  x9, gStatusVisible
    mov  w8, #1
    strb w8, [x9]                      // force visible so _update_status runs
    LEA  x0, lncol_sample
    bl   _nsstr
    mov  x2, x0
    LDG  x0, gTextView
    CALL sel_setString
    LDG  x0, gTextView
    LDG  x1, sel_setSelectedRange
    mov  x2, #8
    mov  x3, #0
    bl   _objc_msgSend
    bl   _update_status
    LDG  x0, gStatusField
    LDG  x1, sel_stringValue
    bl   _objc_msgSend
    bl   _puts_nsstr

    // ---- go to line test ----
    LEA  x0, d_hdr_goto
    bl   _puts
    LEA  x0, goto_sample
    bl   _nsstr
    mov  x2, x0
    LDG  x0, gTextView
    CALL sel_setString
    mov  x0, #3
    bl   _select_line                  // selects line 3, updates status
    LDG  x0, gStatusField
    LDG  x1, sel_stringValue
    bl   _objc_msgSend
    bl   _puts_nsstr
    LEA  x9, gStatusVisible
    strb wzr, [x9]                     // restore hidden

    // ---- date sample ----
    LEA  x0, d_hdr_date
    bl   _puts
    LDG  x0, cls_NSDate
    LDG  x1, sel_date
    bl   _objc_msgSend
    mov  x19, x0
    LDG  x0, cls_NSDateFormatter
    CALL sel_alloc
    CALL sel_init
    mov  x20, x0
    mov  x0, x20
    LDG  x1, sel_setDateStyle
    mov  x2, #2
    bl   _objc_msgSend
    mov  x0, x20
    LDG  x1, sel_setTimeStyle
    mov  x2, #1
    bl   _objc_msgSend
    mov  x0, x20
    LDG  x1, sel_stringFromDate
    mov  x2, x19
    bl   _objc_msgSend
    bl   _puts_nsstr

    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x25, x26, [sp, #64]
    ldp  x29, x30, [sp], #80
    ret

//==============================================================================
// Document helpers
//==============================================================================

    .p2align 2
// _mark_dirty: gDirty = 1; [window setDocumentEdited:YES]
_mark_dirty:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    LEA  x9, gDirty
    mov  w8, #1
    strb w8, [x9]
    LDG  x0, gWindow
    mov  w2, #1
    CALL sel_setDocEdited
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// _clear_dirty: gDirty = 0; [window setDocumentEdited:NO]
_clear_dirty:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    LEA  x9, gDirty
    strb wzr, [x9]
    LDG  x0, gWindow
    mov  w2, #0
    CALL sel_setDocEdited
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// _apply_url: x0 = NSURL* (or nil). Retain into gFileURL, set title + proxy icon.
_apply_url:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    cbz  x19, 1f
    mov  x0, x19
    CALL sel_retain
1:  LDG  x0, gFileURL
    cbz  x0, 2f
    CALL sel_release
2:  LEA  x9, gFileURL
    str  x19, [x9]
    // window representedURL (proxy icon / path)
    LDG  x0, gWindow
    mov  x2, x19
    CALL sel_setRepURL
    // window title
    cbz  x19, 3f
    mov  x0, x19
    CALL sel_lastPathComp
    mov  x2, x0
    LDG  x0, gWindow
    CALL sel_setTitle
    b    4f
3:  LEA  x0, str_untitled
    bl   _nsstr
    mov  x2, x0
    LDG  x0, gWindow
    CALL sel_setTitle
4:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _write_text_to_url: x0 = NSURL* -> w0 = success (writes [textView string], UTF-8)
_write_text_to_url:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    LDG  x0, gTextView
    CALL sel_string
    mov  x20, x0
    mov  x0, x20
    LDG  x1, sel_writeToURL
    mov  x2, x19               // url
    mov  w3, #1                // atomically YES
    mov  x4, #4                // NSUTF8StringEncoding
    mov  x5, #0                // error NULL
    bl   _objc_msgSend
    and  w0, w0, #0xff
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _read_url_to_text: x0 = NSURL* -> w0 = success (loads text; UTF-8, else MacRoman)
_read_url_to_text:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    LDG  x0, cls_NSString
    LDG  x1, sel_strWithContentsURL
    mov  x2, x19
    mov  x3, #4                // UTF-8
    mov  x4, #0
    bl   _objc_msgSend
    mov  x20, x0
    cbnz x20, 1f
    LDG  x0, cls_NSString
    LDG  x1, sel_strWithContentsURL
    mov  x2, x19
    mov  x3, #30               // NSMacOSRomanStringEncoding (any byte -> char)
    mov  x4, #0
    bl   _objc_msgSend
    mov  x20, x0
    cbz  x20, 2f
1:  LDG  x0, gTextView
    mov  x2, x20
    CALL sel_setString
    mov  w0, #1
    b    3f
2:  bl   _NSBeep
    mov  w0, #0
3:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _do_save_as: run NSSavePanel; on OK write + adopt URL. -> w0 = saved?
_do_save_as:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    LDG  x0, cls_NSSavePanel
    CALL sel_savePanel
    mov  x19, x0
    mov  x0, x19
    CALL sel_runModal
    cmp  x0, #1                // NSModalResponseOK
    b.ne 8f
    mov  x0, x19
    CALL sel_URL
    mov  x20, x0
    mov  x0, x20
    bl   _write_text_to_url
    cbz  w0, 8f
    mov  x0, x20
    bl   _apply_url
    bl   _clear_dirty
    mov  w0, #1
    b    9f
8:  mov  w0, #0
9:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _do_save: save to existing URL, else Save As. -> w0 = saved?
_do_save:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    LDG  x0, gFileURL
    cbz  x0, 7f
    bl   _write_text_to_url
    cbz  w0, 6f
    bl   _clear_dirty
    mov  w0, #1
    b    5f
7:  bl   _do_save_as
    b    5f
6:  mov  w0, #0
5:  ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// _prompt_unsaved: if dirty, ask Save/Don't Save/Cancel. -> w0 = 1 proceed / 0 abort
_prompt_unsaved:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    LEA  x9, gDirty
    ldrb w9, [x9]
    cbz  w9, 4f                // not dirty -> proceed
    LDG  x0, cls_NSAlert
    CALL sel_alloc
    CALL sel_init
    mov  x19, x0
    LEA  x0, msg_unsaved
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_setMessageText
    LEA  x0, msg_unsaved_info
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_setInformativeText
    LEA  x0, btn_save
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_addButtonTitle
    LEA  x0, btn_dontsave
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_addButtonTitle
    LEA  x0, btn_cancel
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_addButtonTitle
    mov  x0, x19
    CALL sel_runModal
    mov  x20, x0
    mov  x0, x19
    CALL sel_release
    cmp  x20, #1000            // Save
    b.eq 1f
    cmp  x20, #1001            // Don't Save
    b.eq 2f
    mov  w0, #0                // Cancel -> abort
    b    3f
1:  bl   _do_save             // w0 = saved? (cancelled Save As -> abort)
    b    3f
2:  bl   _clear_dirty         // discard changes, proceed
    mov  w0, #1
    b    3f
4:  mov  w0, #1
3:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

//==============================================================================
// View / status-bar helpers
//==============================================================================

    .p2align 2
// _build_status: create the (initially hidden) status bar view + Ln/Col label.
_build_status:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    // status container view (0,0,800,22)
    LDG  x0, cls_NSView
    CALL sel_alloc
    mov  x19, x0
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #22
    scvtf d3, w9
    mov  x0, x19
    CALL sel_initWithFrame
    mov  x19, x0
    LEA  x9, gStatusView
    str  x19, [x9]
    mov  x0, x19
    LDG  x1, sel_setAutoresizingMask
    mov  w2, #2
    bl   _objc_msgSend
    // hairline separator box (0,21,800,1)
    LDG  x0, cls_NSBox
    CALL sel_alloc
    mov  x20, x0
    fmov d0, xzr
    mov  w9, #21
    scvtf d1, w9
    mov  w9, #800
    scvtf d2, w9
    mov  w9, #1
    scvtf d3, w9
    mov  x0, x20
    CALL sel_initWithFrame
    mov  x20, x0
    mov  x0, x20
    LDG  x1, sel_setBoxType
    mov  w2, #2                        // NSBoxSeparator
    bl   _objc_msgSend
    mov  x0, x20
    LDG  x1, sel_setAutoresizingMask
    mov  w2, #2
    bl   _objc_msgSend
    mov  x0, x19
    LDG  x1, sel_addSubview
    mov  x2, x20
    bl   _objc_msgSend
    // Ln/Col label (8,3,784,16)
    LDG  x0, cls_NSTextField
    CALL sel_alloc
    mov  x21, x0
    mov  w9, #8
    scvtf d0, w9
    mov  w9, #3
    scvtf d1, w9
    mov  w9, #784
    scvtf d2, w9
    mov  w9, #16
    scvtf d3, w9
    mov  x0, x21
    CALL sel_initWithFrame
    mov  x21, x0
    LEA  x9, gStatusField
    str  x21, [x9]
    mov  x0, x21
    LDG  x1, sel_setEditable
    mov  w2, #0
    bl   _objc_msgSend
    mov  x0, x21
    LDG  x1, sel_setBezeled
    mov  w2, #0
    bl   _objc_msgSend
    mov  x0, x21
    LDG  x1, sel_setDrawsBackground
    mov  w2, #0
    bl   _objc_msgSend
    mov  x0, x21
    LDG  x1, sel_setSelectable
    mov  w2, #0
    bl   _objc_msgSend
    mov  x0, x21
    LDG  x1, sel_setAutoresizingMask
    mov  w2, #2
    bl   _objc_msgSend
    // small system font
    LDG  x0, cls_NSFont
    LDG  x1, sel_systemFontOfSize
    mov  w9, #11
    scvtf d0, w9
    bl   _objc_msgSend
    mov  x22, x0
    mov  x0, x21
    LDG  x1, sel_setFont
    mov  x2, x22
    bl   _objc_msgSend
    // initial text
    LEA  x0, status_init
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    LDG  x1, sel_setStringValue
    bl   _objc_msgSend
    // add label to status view
    mov  x0, x19
    LDG  x1, sel_addSubview
    mov  x2, x21
    bl   _objc_msgSend
    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

    .p2align 2
// _relayout: place the in-window menu bar (top 26px), the scroll view, and the
// optional status bar (bottom 22px) inside the content view.
_relayout:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  d8, d9, [sp, #16]              // W / H
    stp  d10, d11, [sp, #32]           // 26 / 22 constants
    LDG  x0, gContentView
    LDG  x1, sel_bounds
    bl   _objc_msgSend
    fmov d8, d2                        // W
    fmov d9, d3                        // H
    mov  w9, #26
    scvtf d10, w9                     // top bar height
    mov  w9, #22
    scvtf d11, w9                     // status bar height
    // menu bar = (0, H-26, W, 26)
    fmov d0, xzr
    fsub d1, d9, d10
    fmov d2, d8
    fmov d3, d10
    LDG  x0, gWinBar
    LDG  x1, sel_setFrame
    bl   _objc_msgSend
    LEA  x9, gStatusVisible
    ldrb w9, [x9]
    cbz  w9, 1f
    // status visible: scroll = (0,22,W,H-26-22)
    fmov d0, xzr
    fmov d1, d11
    fmov d2, d8
    fsub d3, d9, d10
    fsub d3, d3, d11
    LDG  x0, gScroll
    LDG  x1, sel_setFrame
    bl   _objc_msgSend
    // status view = (0,0,W,22)
    fmov d0, xzr
    fmov d1, xzr
    fmov d2, d8
    fmov d3, d11
    LDG  x0, gStatusView
    LDG  x1, sel_setFrame
    bl   _objc_msgSend
    b    2f
1:  // no status: scroll = (0,0,W,H-26)
    fmov d0, xzr
    fmov d1, xzr
    fmov d2, d8
    fsub d3, d9, d10
    LDG  x0, gScroll
    LDG  x1, sel_setFrame
    bl   _objc_msgSend
2:  ldp  d8, d9, [sp, #16]
    ldp  d10, d11, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

    .p2align 2
// _update_status: recompute "Ln n, Col n" from the caret and set the label.
_update_status:
    stp  x29, x30, [sp, #-64]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    LEA  x9, gStatusVisible
    ldrb w9, [x9]
    cbz  w9, 9f                        // hidden -> nothing to do
    // s = [textView string]
    LDG  x0, gTextView
    CALL sel_string
    mov  x19, x0
    // loc = [textView selectedRange].location
    LDG  x0, gTextView
    CALL sel_selectedRange
    mov  x20, x0                       // loc
    // sub = [s substringToIndex:loc]
    mov  x0, x19
    LDG  x1, sel_substringToIndex
    mov  x2, x20
    bl   _objc_msgSend
    mov  x21, x0
    // line = [[sub componentsSeparatedByString:@"\n"] count]
    LEA  x0, str_nl
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    LDG  x1, sel_componentsSep
    bl   _objc_msgSend
    LDG  x1, sel_count
    bl   _objc_msgSend
    mov  x21, x0                       // line
    // lineStart = [s lineRangeForRange:{loc,0}].location
    mov  x0, x19
    LDG  x1, sel_lineRangeForRange
    mov  x2, x20
    mov  x3, #0
    bl   _objc_msgSend
    // col = loc - lineStart + 1
    sub  x22, x20, x0
    add  x22, x22, #1
    // result = [NSString stringWithFormat:@"Ln %ld, Col %ld", line, col]
    LEA  x0, fmt_lncol
    bl   _nsstr
    mov  x23, x0
    LDG  x0, cls_NSString
    LDG  x1, sel_stringWithFormat
    mov  x2, x23
    sub  sp, sp, #16
    str  x21, [sp]                     // variadic args on the stack (Apple arm64)
    str  x22, [sp, #8]
    bl   _objc_msgSend
    add  sp, sp, #16
    mov  x2, x0
    LDG  x0, gStatusField
    LDG  x1, sel_setStringValue
    bl   _objc_msgSend
9:  ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x29, x30, [sp], #64
    ret

    .p2align 2
// _apply_wrap: reconfigure text container / scroller per gWrap.
_apply_wrap:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  d8, d9, [sp, #32]
    LDG  x0, gTextView
    CALL sel_textContainer
    mov  x19, x0                       // container
    LDG  x0, gScroll
    LDG  x1, sel_contentSize
    bl   _objc_msgSend
    fmov d8, d0                        // content width
    LEA  x9, gWrap
    ldrb w9, [x9]
    cbz  w9, 1f
    // WRAP ON
    LDG  x0, gScroll
    LDG  x1, sel_setHasHorizScroller
    mov  w2, #0
    bl   _objc_msgSend
    LDG  x0, gTextView
    LDG  x1, sel_setHorizResizable
    mov  w2, #0
    bl   _objc_msgSend
    LDG  x0, gTextView
    LDG  x1, sel_setAutoresizingMask
    mov  w2, #2
    bl   _objc_msgSend
    mov  x0, x19
    LDG  x1, sel_setWidthTracks
    mov  w2, #1
    bl   _objc_msgSend
    fmov d0, d8
    LEA  x9, d_big
    ldr  d1, [x9]
    mov  x0, x19
    LDG  x1, sel_setContainerSize
    bl   _objc_msgSend
    b    2f
1:  // WRAP OFF
    LDG  x0, gScroll
    LDG  x1, sel_setHasHorizScroller
    mov  w2, #1
    bl   _objc_msgSend
    LDG  x0, gTextView
    LDG  x1, sel_setHorizResizable
    mov  w2, #1
    bl   _objc_msgSend
    LDG  x0, gTextView
    LDG  x1, sel_setAutoresizingMask
    mov  w2, #0
    bl   _objc_msgSend
    mov  x0, x19
    LDG  x1, sel_setWidthTracks
    mov  w2, #0
    bl   _objc_msgSend
    LEA  x9, d_big
    ldr  d0, [x9]
    ldr  d1, [x9]
    mov  x0, x19
    LDG  x1, sel_setContainerSize
    bl   _objc_msgSend
2:  ldp  x19, x20, [sp, #16]
    ldp  d8, d9, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

//==============================================================================
// MPController method implementations (IMPs).  Signature: (id self, SEL _cmd, ...)
//==============================================================================

    .p2align 2
// BOOL applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)
_imp_appTermLast:
    mov  w0, #1
    ret

    .p2align 2
// void newDoc: -> dirty-check, then clear text + reset to Untitled
_imp_newDoc:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    bl   _prompt_unsaved
    cbz  w0, 1f
    LEA  x0, str_empty
    bl   _nsstr
    mov  x2, x0
    LDG  x0, gTextView
    CALL sel_setString
    mov  x0, #0
    bl   _apply_url            // nil -> "Untitled"
    bl   _clear_dirty
1:  ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// void openDoc: -> dirty-check, NSOpenPanel, load file, adopt URL
_imp_openDoc:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    bl   _prompt_unsaved
    cbz  w0, 1f
    LDG  x0, cls_NSOpenPanel
    CALL sel_openPanel
    mov  x19, x0
    mov  x0, x19
    mov  w2, #0
    CALL sel_setAllowsMultiple
    mov  x0, x19
    CALL sel_runModal
    cmp  x0, #1
    b.ne 1f
    mov  x0, x19
    CALL sel_URL
    mov  x19, x0               // url
    mov  x0, x19
    bl   _read_url_to_text
    cbz  w0, 1f
    mov  x0, x19
    bl   _apply_url
    bl   _clear_dirty
1:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// void saveDoc:
_imp_saveDoc:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    bl   _do_save
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// void saveAsDoc:
_imp_saveAsDoc:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    bl   _do_save_as
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// void textDidChange: -> mark document dirty + refresh Ln/Col
_imp_textDidChange:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    bl   _mark_dirty
    bl   _update_status
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// void textViewDidChangeSelection: -> refresh Ln/Col
_imp_selChange:
    b    _update_status

    .p2align 2
// BOOL validateMenuItem: -> keep enabled, drive toggle checkmarks
_imp_validateMenuItem:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x2                       // menu item
    mov  x0, x19
    LDG  x1, sel_action
    bl   _objc_msgSend
    mov  x20, x0                       // action SEL
    LDG  x9, sel_toggleWordWrap
    cmp  x20, x9
    b.ne 1f
    LEA  x9, gWrap
    ldrb w9, [x9]
    b    4f
1:  LDG  x9, sel_toggleStatusBar
    cmp  x20, x9
    b.ne 2f
    LEA  x9, gStatusVisible
    ldrb w9, [x9]
    b    4f
2:  LDG  x9, sel_toggleLineNumbers
    cmp  x20, x9
    b.ne 3f
    LEA  x9, gLineNumbers
    ldrb w9, [x9]
    b    4f
3:  mov  w0, #1                        // not a toggle: enabled, no state change
    b    5f
4:  mov  x0, x19
    LDG  x1, sel_setState
    mov  w2, w9
    bl   _objc_msgSend
    mov  w0, #1
5:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// BOOL windowShouldClose:
_imp_windowShouldClose:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    bl   _prompt_unsaved
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// NSApplicationTerminateReply applicationShouldTerminate: (0=Cancel, 1=Now)
_imp_appShouldTerminate:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    bl   _prompt_unsaved
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// void toggleWordWrap: -> flip gWrap, reconfigure text container
_imp_toggleWordWrap:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    LEA  x9, gWrap
    ldrb w8, [x9]
    eor  w8, w8, #1
    strb w8, [x9]
    bl   _apply_wrap
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// void toggleStatusBar: -> flip gStatusVisible, add/remove status view
_imp_toggleStatusBar:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    LEA  x9, gStatusVisible
    ldrb w8, [x9]
    eor  w8, w8, #1
    strb w8, [x9]
    cbz  w8, 1f
    // now visible: add subview, relayout, refresh
    LDG  x0, gContentView
    LDG  x1, sel_addSubview
    LDG  x2, gStatusView
    bl   _objc_msgSend
    bl   _relayout
    bl   _update_status
    b    2f
1:  // now hidden: remove subview, relayout
    LDG  x0, gStatusView
    CALL sel_removeFromSuper
    bl   _relayout
2:  ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// _select_line: x0 = 1-based line number -> move caret to its start, scroll to it
_select_line:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    mov  x19, x0                       // remaining = n
    LDG  x0, gTextView
    CALL sel_string
    mov  x20, x0                       // s
    mov  x0, x20
    LDG  x1, sel_length
    bl   _objc_msgSend
    mov  x22, x0                       // len
    mov  x21, #0                       // start
    sub  x19, x19, #1                  // advance (n-1) lines
1:  cbz  x19, 2f
    cmp  x21, x22
    b.hs 2f
    mov  x0, x20
    LDG  x1, sel_lineRangeForRange
    mov  x2, x21
    mov  x3, #0
    bl   _objc_msgSend                 // x0=loc, x1=length (incl terminator)
    add  x21, x0, x1                   // start = next line
    sub  x19, x19, #1
    b    1b
2:  cmp  x21, x22
    csel x21, x22, x21, hs             // clamp to length
    LDG  x0, gTextView
    LDG  x1, sel_setSelectedRange
    mov  x2, x21
    mov  x3, #0
    bl   _objc_msgSend
    LDG  x0, gTextView
    LDG  x1, sel_scrollRangeToVisible
    mov  x2, x21
    mov  x3, #0
    bl   _objc_msgSend
    bl   _update_status
    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

    .p2align 2
// void gotoLine: -> modal alert with a numeric field, then jump
_imp_gotoLine:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    LDG  x0, cls_NSAlert
    CALL sel_alloc
    CALL sel_init
    mov  x19, x0
    LEA  x0, msg_goto
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_setMessageText
    LEA  x0, msg_goto_info
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_setInformativeText
    LEA  x0, btn_go
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_addButtonTitle
    LEA  x0, btn_cancel
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_addButtonTitle
    // numeric accessory field (0,0,200,24)
    LDG  x0, cls_NSTextField
    CALL sel_alloc
    mov  x20, x0
    fmov d0, xzr
    fmov d1, xzr
    mov  w9, #200
    scvtf d2, w9
    mov  w9, #24
    scvtf d3, w9
    mov  x0, x20
    CALL sel_initWithFrame
    mov  x20, x0
    mov  x0, x19
    LDG  x1, sel_setAccessoryView
    mov  x2, x20
    bl   _objc_msgSend
    // focus the field
    mov  x0, x19
    CALL sel_window
    mov  x2, x20
    LDG  x1, sel_setInitialFirstResponder
    bl   _objc_msgSend
    // run
    mov  x0, x19
    CALL sel_runModal
    mov  x22, x0                       // response
    mov  x0, x20
    LDG  x1, sel_integerValue
    bl   _objc_msgSend
    mov  x21, x0                       // n
    mov  x0, x19
    CALL sel_release
    cmp  x22, #1000
    b.ne 1f
    cmp  x21, #1
    b.lt 1f
    mov  x0, x21
    bl   _select_line
1:  ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

    .p2align 2
// void insertDateTime: -> insert localized date+time at the caret (undo-aware)
_imp_insertDateTime:
    stp  x29, x30, [sp, #-64]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    // now = [NSDate date]
    LDG  x0, cls_NSDate
    LDG  x1, sel_date
    bl   _objc_msgSend
    mov  x19, x0
    // fmt = [[NSDateFormatter alloc] init]
    LDG  x0, cls_NSDateFormatter
    CALL sel_alloc
    CALL sel_init
    mov  x20, x0
    mov  x0, x20
    LDG  x1, sel_setDateStyle
    mov  x2, #2                        // NSDateFormatterMediumStyle
    bl   _objc_msgSend
    mov  x0, x20
    LDG  x1, sel_setTimeStyle
    mov  x2, #1                        // NSDateFormatterShortStyle
    bl   _objc_msgSend
    // str = [fmt stringFromDate:now]
    mov  x0, x20
    LDG  x1, sel_stringFromDate
    mov  x2, x19
    bl   _objc_msgSend
    mov  x21, x0
    mov  x0, x20
    CALL sel_release
    // range = [textView selectedRange]
    LDG  x0, gTextView
    LDG  x1, sel_selectedRange
    bl   _objc_msgSend
    mov  x22, x0                       // loc
    mov  x23, x1                       // len
    // guard undo/notifications
    LDG  x0, gTextView
    LDG  x1, sel_shouldChangeText
    mov  x2, x22
    mov  x3, x23
    mov  x4, x21
    bl   _objc_msgSend
    and  w0, w0, #0xff
    cbz  w0, 1f
    // [[textView textStorage] replaceCharactersInRange:range withString:str]
    LDG  x0, gTextView
    CALL sel_textStorage
    mov  x24, x0
    mov  x0, x24
    LDG  x1, sel_replaceChars
    mov  x2, x22
    mov  x3, x23
    mov  x4, x21
    bl   _objc_msgSend
    LDG  x0, gTextView
    CALL sel_didChangeText
1:  ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x29, x30, [sp], #64
    ret

    .p2align 2
// void toggleLineNumbers: -> flip gLineNumbers, show/hide the ruler
_imp_toggleLineNumbers:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    LEA  x9, gLineNumbers
    ldrb w8, [x9]
    eor  w8, w8, #1
    strb w8, [x9]
    LDG  x0, gScroll
    LDG  x1, sel_setRulersVisible
    mov  w2, w8
    bl   _objc_msgSend
    ldp  x29, x30, [sp], #16
    ret

    .p2align 2
// void showHelp: -> modal help panel
_imp_showHelp:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    LDG  x0, cls_NSAlert
    CALL sel_alloc
    CALL sel_init
    mov  x19, x0
    LEA  x0, msg_help
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_setMessageText
    LEA  x0, msg_help_info
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_setInformativeText
    LEA  x0, btn_ok
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    CALL sel_addButtonTitle
    mov  x0, x19
    CALL sel_runModal
    mov  x0, x19
    CALL sel_release
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _open_path: x0 = path NSString -> dirty-check, load file, adopt URL. w0 = ok
_open_path:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    bl   _prompt_unsaved
    cbz  w0, 8f
    LDG  x0, cls_NSURL
    LDG  x1, sel_fileURLWithPath
    mov  x2, x19
    bl   _objc_msgSend
    mov  x19, x0
    mov  x0, x19
    bl   _read_url_to_text
    cbz  w0, 8f
    mov  x0, x19
    bl   _apply_url
    bl   _clear_dirty
    mov  w0, #1
    b    9f
8:  mov  w0, #0
9:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// BOOL application:openFile: (self,_cmd,sender,path)
_imp_openFile:
    mov  x0, x3
    b    _open_path

    .p2align 2
// NSDragOperation draggingEntered:/draggingUpdated: -> Copy
_imp_dragEntered:
    mov  w0, #1                        // NSDragOperationCopy
    ret

    .p2align 2
// BOOL performDragOperation: -> open the first dropped file
_imp_performDrag:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x0, x2                        // sender
    LDG  x1, sel_draggingPasteboard
    bl   _objc_msgSend
    mov  x19, x0
    LEA  x0, pbtype_files
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    LDG  x1, sel_propertyListForType
    bl   _objc_msgSend
    mov  x19, x0                       // files array
    cbz  x19, 8f
    mov  x0, x19
    LDG  x1, sel_objectAtIndex
    mov  x2, #0
    bl   _objc_msgSend
    bl   _open_path
    mov  w0, #1
    b    9f
8:  mov  w0, #0
9:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// _line_at: x0 = string, x1 = char index -> x0 = 1-based line number
_line_at:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    LDG  x1, sel_substringToIndex
    mov  x2, x20
    bl   _objc_msgSend
    mov  x19, x0
    LEA  x0, str_nl
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    LDG  x1, sel_componentsSep
    bl   _objc_msgSend
    LDG  x1, sel_count
    bl   _objc_msgSend
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

    .p2align 2
// void drawHashMarksAndLabelsInRect: (MPRuler) -> draw logical line numbers
// Registers: x19=layoutManager x20=string x21=glyphIdx x22=glyphEnd x23=lineNo
//            x24=textContainer w25=first w26=isStart  d8=originY d9=visibleY
//            effective glyph range buffer at [x29,#112]
_imp_ruler_draw:
    stp  x29, x30, [sp, #-128]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]
    stp  d8,  d9,  [sp, #80]
    stp  d10, d11, [sp, #96]
    LDG  x0, gTextView
    LDG  x1, sel_layoutManager
    bl   _objc_msgSend
    mov  x19, x0
    LDG  x0, gTextView
    CALL sel_textContainer
    mov  x24, x0
    LDG  x0, gTextView
    CALL sel_string
    mov  x20, x0
    LDG  x0, gTextView
    LDG  x1, sel_textContainerOrigin
    bl   _objc_msgSend
    fmov d8, d1                        // container origin y
    LDG  x0, gTextView
    LDG  x1, sel_visibleRect
    bl   _objc_msgSend
    fmov d9, d1                        // visible origin y (rect stays in v0-v3)
    mov  x0, x19
    LDG  x1, sel_glyphRangeForRect
    mov  x2, x24
    bl   _objc_msgSend                 // -> x0=loc, x1=len (visible rect in v0-v3)
    mov  x21, x0
    add  x22, x0, x1
    cmp  x21, x22
    b.hs 5f
    // lineNo = _line_at(string, charIndexForGlyph(glyphStart))
    mov  x0, x19
    LDG  x1, sel_charIndexForGlyph
    mov  x2, x21
    bl   _objc_msgSend
    mov  x1, x0
    mov  x0, x20
    bl   _line_at
    mov  x23, x0
    mov  w25, #1                       // first fragment
1:  cmp  x21, x22
    b.hs 5f
    // c = charIndexForGlyph(idx); isStart = (c==0 || string[c-1]=='\n')
    mov  x0, x19
    LDG  x1, sel_charIndexForGlyph
    mov  x2, x21
    bl   _objc_msgSend
    cbz  x0, 2f
    sub  x9, x0, #1
    mov  x0, x20
    LDG  x1, sel_characterAtIndex
    mov  x2, x9
    bl   _objc_msgSend
    cmp  x0, #10
    cset w26, eq
    b    3f
2:  mov  w26, #1
3:  cbz  w26, 4f                       // not a logical line start -> no number
    cbnz w25, 31f                      // first fragment: don't pre-increment
    add  x23, x23, #1
31: // draw number for this line
    add  x3, x29, #112                 // &effectiveRange
    mov  x0, x19
    LDG  x1, sel_lineFragRect
    mov  x2, x21
    bl   _objc_msgSend                 // NSRect in v0-v3
    fadd d10, d1, d8                   // y = fragY + originY
    fsub d10, d10, d9                  //   - visibleY
    LEA  x0, fmt_ld
    bl   _nsstr
    mov  x2, x0
    LDG  x0, cls_NSString
    LDG  x1, sel_stringWithFormat
    sub  sp, sp, #16
    str  x23, [sp]
    bl   _objc_msgSend
    add  sp, sp, #16
    mov  w9, #4
    scvtf d0, w9                       // x = 4
    fmov d1, d10                       // y
    LDG  x2, gRulerAttrs               // adaptive color + small font
    LDG  x1, sel_drawAtPoint
    bl   _objc_msgSend
    b    41f
4:  // still need the effective range to advance
    add  x3, x29, #112
    mov  x0, x19
    LDG  x1, sel_lineFragRect
    mov  x2, x21
    bl   _objc_msgSend
41: mov  w25, #0
    ldr  x9,  [x29, #112]              // eff.location
    ldr  x10, [x29, #120]             // eff.length
    add  x11, x9, x10
    add  x12, x21, #1
    cmp  x11, x12
    csel x21, x11, x12, hi             // ensure forward progress
    b    1b
5:  ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x25, x26, [sp, #64]
    ldp  d8,  d9,  [sp, #80]
    ldp  d10, d11, [sp, #96]
    ldp  x29, x30, [sp], #128
    ret

    .p2align 2
// void winMenu: -> pop the in-window menu for the clicked bar button, below it
_imp_winMenu:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x2                       // sender (button)
    mov  x0, x19
    LDG  x1, sel_tag
    bl   _objc_msgSend                 // x0 = tag (0..4)
    LEA  x9, gWinMenus
    ldr  x20, [x9, x0, lsl #3]         // menu = gWinMenus[tag]
    // [menu popUpMenuPositioningItem:nil atLocation:(0,0) inView:sender]
    mov  x0, x20
    LDG  x1, sel_popUpPositioning
    mov  x2, #0
    fmov d0, xzr
    fmov d1, xzr
    mov  x3, x19
    bl   _objc_msgSend
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret
