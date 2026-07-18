import TipKit

/// Points at the "Select photo" toolbar item on CreateView so users discover
/// they can pick their own photo. Invalidated once a photo is chosen.
struct SelectPhotoTip: Tip {
    var title: Text {
        Text("Tap Select photo to choose one, then watch it transform into this style.")
    }
}
