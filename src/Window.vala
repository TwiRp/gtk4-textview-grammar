/**
 * MIT License
 *
 * Copyright (c) 2022 TwiRpin Around
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

namespace TwiRpin {
    public class NextMD : Adw.ApplicationWindow {
        private static NextMD? _instance;
        private Editor source_view;
        public Adw.HeaderBar toolbar;
        public Adw.Leaflet window_leaflet;
        public Adw.Flap editor_view;

        public NextMD (Gtk.Application app) {
            Object (application: app);
            _instance = this;
            build_ui ();
        }

        private void build_ui () {
            toolbar = new Adw.HeaderBar ();
            toolbar.set_show_start_title_buttons (true);
            toolbar.set_title_widget (new Gtk.Label ("NextMD"));
            // Box to hold everything together
            var window_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            var editor_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            editor_view = new Adw.Flap ();

            // Scroll view to hold contents
            var scroll_box = new Gtk.ScrolledWindow ();
            scroll_box.vexpand = true;
            scroll_box.hexpand = true;
            source_view = new Editor ();
            // Create a GtkSourceView and create a markdown buffer
            source_view = new Editor ();
            // Set placeholder text
            source_view.buffer.text = "# Hello DEV!\n\nYou can type away.\n";
            // Add the GtkSourceView to the Scroll Box
            scroll_box.set_child (source_view);

            editor_view.set_flap (new Sheets ());
            editor_view.set_content (scroll_box);
            editor_view.set_flap_position (Gtk.PackType.START);
            editor_view.set_fold_policy (Adw.FlapFoldPolicy.AUTO);
            editor_view.set_transition_type (Adw.FlapTransitionType.SLIDE);

            editor_box.append (toolbar);
            editor_box.append (editor_view);

            window_leaflet = new Adw.Leaflet ();
            var lib_leaf = window_leaflet.append (new Library ());
            var edit_lead = window_leaflet.append (editor_box);
            window_leaflet.set_homogeneous (false);
            window_leaflet.set_transition_type (Adw.LeafletTransitionType.SLIDE);

            window_box.append (window_leaflet);

            set_content (window_box);
            set_default_size (600, 320);
        }
    }
}