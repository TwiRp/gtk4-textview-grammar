project('grammarview', ['vala', 'c'],
  version: '0.0.1'
)

# Find linkgrammar (under library name)
cc = meson.get_compiler('c')
linkgrammar = cc.find_library('liblink-grammar', required: false)
# If we can't find the library, double check without the "lib" prefix.
if linkgrammar.found() == false
    cc = meson.get_compiler('c')
    linkgrammar = cc.find_library('link-grammar', required: true)
endif

# Define our dependencies
example_deps = [ dependency('gtk4'), dependency('gtksourceview-5'), dependency('gee-0.8'), linkgrammar ]

# Tell the compiler where our custom Vala Bindings are
add_project_arguments(['--vapidir', join_paths(meson.current_source_dir(), 'vapi')], language: 'vala')

# Define our executable and its sources
executable(
    'grammarview',
    'src/Application.vala',
    'src/GrammarChecker.vala',
    'src/Functions.vala',
    'src/Markdown.vala',
    dependencies: example_deps,
    vala_args: [
        meson.source_root() + '/vapi/linkgrammar.vapi'
    ],
    install: false
)