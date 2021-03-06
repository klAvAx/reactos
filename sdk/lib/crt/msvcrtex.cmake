
include_directories(include/internal/mingw-w64)

list(APPEND MSVCRTEX_SOURCE
    startup/crtexe.c
    startup/wcrtexe.c
    startup/crt_handler.c
    startup/crtdll.c
    startup/_newmode.c
    startup/wildcard.c
    startup/tlssup.c
    startup/mingw_helpers.c
    startup/natstart.c
    startup/charmax.c
    startup/merr.c
    startup/atonexit.c
    startup/dllmain.c
    startup/txtmode.c
    startup/pesect.c
    startup/tlsmcrt.c
    startup/tlsthrd.c
    startup/tlsmthread.c
    startup/cinitexe.c
    startup/gs_support.c
    startup/dll_argv.c
    startup/dllargv.c
    startup/wdllargv.c
    startup/crt0_c.c
    startup/crt0_w.c
    startup/dllentry.c
    startup/reactos.c
    misc/dbgrpt.cpp
    misc/fltused.c
    misc/isblank.c
    misc/iswblank.c
    misc/ofmt_stub.c
    stdio/acrt_iob_func.c)

if(MSVC)
    list(APPEND MSVCRTEX_SOURCE
        startup/threadSafeInit.c)
else()
    list(APPEND MSVCRTEX_SOURCE
        startup/pseudo-reloc.c
        startup/pseudo-reloc-list.c)
endif()

if(ARCH STREQUAL "i386")
    list(APPEND MSVCRTEX_ASM_SOURCE
        except/i386/chkstk_asm.s
        except/i386/chkstk_ms.s
        math/i386/ftol2_asm.s
        math/i386/alldiv_asm.s)
    list(APPEND MSVCRTEX_SOURCE
        math/i386/ci.c
        math/i386/cicos.c
        math/i386/cilog.c
        math/i386/cipow.c
        math/i386/cisin.c
        math/i386/cisqrt.c)
    if (GCC AND CLANG)
        # CLang performs some optimisations requiring those funtions
        list(APPEND MSVCRTEX_ASM_SOURCE
            math/i386/ceilf.S
            math/i386/exp2_asm.s
            math/i386/floorf.S)
        list(APPEND MSVCRTEX_SOURCE
            math/i386/sqrtf.c)
    endif()
elseif(ARCH STREQUAL "amd64")
    list(APPEND MSVCRTEX_ASM_SOURCE
        except/amd64/chkstk_ms.s)
elseif(ARCH STREQUAL "arm")
    list(APPEND MSVCRTEX_SOURCE
        math/arm/__rt_sdiv.c
        math/arm/__rt_sdiv64_worker.c
        math/arm/__rt_udiv.c
        math/arm/__rt_udiv64_worker.c
    )
    list(APPEND MSVCRTEX_ASM_SOURCE
        except/arm/chkstk_asm.s
        math/arm/__dtoi64.s
        math/arm/__dtou64.s
        math/arm/__i64tod.s
        math/arm/__i64tos.s
        math/arm/__stoi64.s
        math/arm/__stou64.s
        math/arm/__u64tod.s
        math/arm/__u64tos.s
        math/arm/__rt_sdiv64.s
        math/arm/__rt_srsh.s
        math/arm/__rt_udiv64.s
    )
endif()

if(MSVC)
    list(APPEND MSVCRTEX_SOURCE startup/mscmain.c)
else()
    list(APPEND MSVCRTEX_SOURCE startup/gccmain.c)
endif()

set_source_files_properties(${MSVCRTEX_ASM_SOURCE} PROPERTIES COMPILE_DEFINITIONS "_DLL;_MSVCRTEX_")
add_asm_files(msvcrtex_asm ${MSVCRTEX_ASM_SOURCE})

add_library(msvcrtex ${MSVCRTEX_SOURCE} ${msvcrtex_asm})
target_compile_definitions(msvcrtex PRIVATE _DLL _MSVCRTEX_)

# Link msvcrtex to the "real" msvcrt.dll library. See msvcrt.dll CMakeLists.txt to see what really happens here
target_link_libraries(msvcrtex libmsvcrt_real libkernel32)

if(GCC OR CLANG)
    target_compile_options(msvcrtex PRIVATE $<$<COMPILE_LANGUAGE:C>:-Wno-main>)
    if(LTCG)
        target_compile_options(msvcrtex PRIVATE -fno-lto)
    endif()
endif()

set_source_files_properties(startup/crtdll.c PROPERTIES COMPILE_DEFINITIONS CRTDLL)
set_source_files_properties(startup/crtexe.c
                            startup/wcrtexe.c PROPERTIES COMPILE_DEFINITIONS _M_CEE_PURE)

if(NOT MSVC)
    target_link_libraries(msvcrtex oldnames)
endif()

if(STACK_PROTECTOR)
    target_link_libraries(msvcrtex gcc_ssp)
endif()

add_dependencies(msvcrtex psdk asm)
