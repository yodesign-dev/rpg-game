'use client'

import { useState } from 'react'
import AccountActions from './AccountActions'

export default function SettingsMenu({
  characterId,
  characterName,
}: {
  characterId: string
  characterName: string
}) {
  const [open, setOpen] = useState(false)

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Cài đặt"
        className="w-[34px] h-[34px] rounded-full bg-white/[0.06] border border-white/10
          flex items-center justify-center hover:bg-white/[0.1] transition-colors"
      >
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#b9b3c4" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="3" />
          <path d="M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.4-2.3.9a7 7 0 0 0-2-1.2L14.2 3h-4.4l-.4 2.6a7 7 0 0 0-2 1.2l-2.3-.9-2 3.4 2 1.5A7 7 0 0 0 5 12a7 7 0 0 0 .1 1.2l-2 1.5 2 3.4 2.3-.9a7 7 0 0 0 2 1.2l.4 2.6h4.4l.4-2.6a7 7 0 0 0 2-1.2l2.3.9 2-3.4-2-1.5c.1-.4.1-.8.1-1.2Z" />
        </svg>
      </button>

      {open && (
        <div className="fixed inset-0 z-40" role="presentation">
          <button
            type="button"
            aria-label="Đóng"
            onClick={() => setOpen(false)}
            className="absolute inset-0 bg-black/50"
          />
          <div
            className="absolute left-4 right-4 top-16 max-w-xs mx-auto rounded-2xl
              bg-[#141118] border border-white/10 p-4 shadow-2xl"
          >
            <AccountActions characterId={characterId} characterName={characterName} />
          </div>
        </div>
      )}
    </>
  )
}
