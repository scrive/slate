module Doc.API.V2 (
  documentAPIV2
) where

import Happstack.Server.Types
import Happstack.StaticRouting

import Doc.API.V2.Calls
import Kontra
import KontraPrelude
import Routing

documentAPIV2 ::  Route (Kontra Response)
documentAPIV2  = dir "documents" $ choice [
    dir "new"             $ hPost $ toK0 $ docApiV2New
  , dir "newfromtemplate" $ hPost $ toK1 $ docApiV2NewFromTemplate

  , dir "list"      $ hGet $ toK0 $ docApiV2List

  , param $ dir "get"                 $ hGet $ toK1 $ docApiV2Get
  , param $ dir "getbyshortid"        $ hGet $ toK1 $ docApiV2GetByShortID
  , param $ dir "history"             $ hGet $ toK1 $ docApiV2History
  , param $ dir "evidenceattachments" $ hGet $ toK1 $ docApiV2EvidenceAttachments

  , param $ dir "update"          $ hPost $ toK1 $ docApiV2Update
  , param $ dir "setfile"         $ hPost $ toK1 $ docApiV2SetFile
  , param $ dir "removepages"     $ hPost $ toK1 $ docApiV2RemovePages
  , param $ dir "start"           $ hPost $ toK1 $ docApiV2Start
  , param $ dir "prolong"         $ hPost $ toK1 $ docApiV2Prolong
  , param $ dir "cancel"          $ hPost $ toK1 $ docApiV2Cancel
  , param $ dir "trash"           $ hPost $ toK1 $ docApiV2Trash
  , param $ dir "delete"          $ hPost $ toK1 $ docApiV2Delete
  , param $ dir "remind"          $ hPost $ toK1 $ docApiV2Remind
  , param $ dir "forward"         $ hPost $ toK1 $ docApiV2Forward
  , param $ dir "setattachments"  $ hPost $ toK1 $ docApiV2SetAttachments
  , param $ dir "setautoreminder" $ hPost $ toK1 $ docApiV2SetAutoReminder
  , param $ dir "clone"           $ hPost $ toK1 $ docApiV2Clone
  , param $ dir "restart"         $ hPost $ toK1 $ docApiV2Restart
  , param $ dir "callback"        $ hPost $ toK1 $ docApiV2Callback

  , param $ dir "files" $ dir "main" $ hGet $ toK2 $ docApiV2FilesMain
  , param $ dir "files"              $ hGet $ toK3 $ docApiV2FilesGet

  , param $ dir "texts" $ hGet $ toK2 $ docApiV2Texts

  , param $ param $ dir "sign"                    $ hPost $ toK2 $ docApiV2SigSign
  , param $ param $ dir "check"                   $ hPost $ toK2 $ docApiV2SigCheck
  , param $ param $ dir "setauthenticationtoview" $ hPost $ toK2 $ docApiV2SigSetAuthenticationToView
  , param $ param $ dir "setauthenticationtosign" $ hPost $ toK2 $ docApiV2SigSetAuthenticationToSign
  , param $ param $ dir "reject"                  $ hPost $ toK2 $ docApiV2SigReject
  , param $ param $ dir "sendsmspin"              $ hPost $ toK2 $ docApiV2SigSendSmsPin
  , param $ param $ dir "setattachment"           $ hPost $ toK2 $ docApiV2SigSetAttachment
  , param $ param $ dir "signing" $ dir "check"   $ hGet  $ toK2 $ docApiV2SigSigningStatusCheck
  , param $ param $ dir "signing" $ dir "cancel"  $ hPost $ toK2 $ docApiV2SigSigningCancel
  , param $ param $ dir "signing" $ dir "highlight" $ hPost $ toK2 $ docApiV2SetHighlightForPage
  ]
