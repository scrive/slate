module Component.Theme.Data exposing (ColorPair, OutMsg, Theme, ThemeColors)

import Color exposing (Color)
import Component.Input.SaveButton as SaveButton


type alias ColorPair =
    { backgroundColor : Color
    , textColor : Color
    }


type alias Theme =
    { id : String
    , name : String
    , logo : String
    , font : String
    , themeColors : ThemeColors
    }


type alias ThemeColors =
    { brandColors : ColorPair
    , actionColors : ColorPair
    , secondaryActionColors : ColorPair
    , positiveColors : ColorPair
    , negativeColors : ColorPair
    }


type alias OutMsg =
    SaveButton.OutMsg Theme
