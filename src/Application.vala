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
    public class GrammarCheck : Gtk.Application {
        private GtkSource.View source_view;
        private GtkSource.Buffer source_buffer;
        private Markdown markdown_enrichment;
        private GrammarChecker grammar_enrichment;

        protected override void activate () {
            // Grab application Window
            var window = new Gtk.ApplicationWindow (this);
            window.set_title ("GrammarChecker");
            window.set_default_size (600, 320);

            // Scroll view to hold contents
            var scroll_box = new Gtk.ScrolledWindow ();
            // Get a pointer to the Markdown Language
            var manager = GtkSource.LanguageManager.get_default ();
            var language = manager.guess_language (null, "text/markdown");

            // Create a GtkSourceView and create a markdown buffer
            source_view = new GtkSource.View ();
            source_buffer = new GtkSource.Buffer.with_language (language);
            source_buffer.highlight_syntax = true;
            source_view.set_buffer (source_buffer);
            source_view.set_wrap_mode (Gtk.WrapMode.WORD);
            // Set placeholder text
            source_buffer.text = "# Hello DEV!\n\nYou can type away.\n";
            // Add the GtkSourceView to the Scroll Box
            scroll_box.set_child (source_view);

            // Attach markdown enrichment
            markdown_enrichment = new Markdown ();
            markdown_enrichment.attach (source_view);

            // Attack grammar checker
            grammar_enrichment = new GrammarChecker ();
            grammar_enrichment.attach (source_view);

            Timeout.add (250, () => {
                markdown_enrichment.recheck_all ();
                grammar_enrichment.recheck_all ();
                return false;
            });

            // Sign up for updates
            source_buffer.changed.connect (() => {
                markdown_enrichment.recheck_all ();
                grammar_enrichment.recheck_all ();
            });

            window_removed.connect (() => {
                markdown_enrichment.detach ();
                grammar_enrichment.detach ();
            });

            // Populate the Window
            window.child = scroll_box;
            window.present ();
        }

        public static int main (string[] args) {
            return new GrammarCheck ().run (args);
        }
    }
}