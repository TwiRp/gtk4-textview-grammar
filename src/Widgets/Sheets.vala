namespace TwiRpin {
    public class Sheets : Gtk.Box {
        private Gtk.Box _view;
        public Sheets () {
            orientation = Gtk.Orientation.VERTICAL;
            spacing = 0;
            vexpand = true;
            _view = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var scrolled_box = new Gtk.ScrolledWindow ();
            scrolled_box.hexpand = false;
            scrolled_box.width_request = 200;
            scrolled_box.vexpand = true;
            scrolled_box.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled_box.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scrolled_box.set_child (_view);
            append (scrolled_box);

            for (int i = 0; i < 100; i++) {
                _view.append (new Gtk.Button.with_label ("Button %d".printf (i)));
            }
            width_request = 200;
        }
    }
}