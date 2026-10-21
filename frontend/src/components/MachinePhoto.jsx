// The photo of the machine an exercise is done on (Settings → Features → Machine settings): taken at
// the gym and kept with the exercise's settings (S.exPhotos, keyed by exercise id), so the right
// machine is recognised at a glance next week and in a gym seen once. The same path as a custom
// exercise's picture (CustomMediaField.jsx useMediaPicker): ingested, kept in the local store as
// pending, uploaded by the media sync, referenced for the server's clean-up (api/media.js) and
// carried by the zip backup.
import { useEffect, useRef } from 'react'
import { useStore } from '../store/useStore.js'
import { t } from '../lib/i18n.js'
import { mediaStore } from '../lib/media-store.js'
import { useMediaPicker } from './CustomMediaField.jsx'
import { CustomThumb, MediaView } from './CustomMedia.jsx'
import { Row, Button } from './ui.jsx'

/**
 * Whether the server keeps a machine photo, as it says in /api/config
 * (`media.machinePhotos`): an older one would sweep a file only exPhotos names. A config not
 * known yet, a guest or a phone in local mode keep the file on the device either way.
 */
export const serverTakesMachinePhotos = (user, config) => !user || !config || !config.media || !!config.media.machinePhotos

/** The photo itself, large, at the top of the machine settings sheet. */
export function MachinePhotoView({ m, name }) {
  return <MediaView m={m} cls="exmedia machine-photo" name={name} />
}

/** The small picture in the line under an exercise. */
export function MachineThumb({ m }) {
  return <span className="exnote-photo"><CustomThumb ex={{ custom: true, media: m }} /></span>
}

/** The photo row of the machine settings sheet: Add / Change / Remove, a photo only. */
export function MachinePhotoField({ photo, onChange }) {
  const user = useStore(s => s.user)
  const config = useStore(s => s.config)
  const { pick, busy, note, showAdd, canAdd } = useMediaPicker()
  const fileRef = useRef(null)
  // The picked file stays out of the local clean-up while the sheet is open (as in the editor of
  // a custom exercise): it is only referenced once Save writes it.
  const mainHash = photo?.hash, posterHash = photo?.poster?.hash
  useEffect(() => {
    if (!mainHash) return undefined
    return mediaStore.hold([mainHash, posterHash])
  }, [mainHash, posterHash])
  const offered = showAdd && serverTakesMachinePhotos(user, config)
  if (!offered && !photo) return null

  const onFile = async ev => {
    const file = ev.target.files && ev.target.files[0]
    ev.target.value = ''
    const got = await pick(file)
    if (got) onChange(got)
  }

  return <>
    <Row icon="image" iconTint="var(--blue)" title={t('Photo of the machine')}
      subtitle={photo ? null : t('Optional. To spot the right machine at a glance.')}>
      <div className="cmf-act">
        {photo && <span className="cmf-thumb"><CustomThumb ex={{ custom: true, media: photo }} /></span>}
        {offered && <Button variant="tinted" size="sm" icon={busy ? undefined : 'image'} disabled={!canAdd} onClick={() => fileRef.current?.click()}>
          {busy ? t('Loading…') : photo ? t('Change') : t('Add')}
        </Button>}
        {photo && <Button variant="ghost" size="sm" icon="xmark" aria-label={t('Remove')} title={t('Remove')} disabled={busy} onClick={() => onChange(null)} />}
      </div>
    </Row>
    <input ref={fileRef} type="file" accept="image/*" hidden onChange={onFile} />
    {note && <div className="small dim cmf-note">{note}</div>}
  </>
}
