import { redirect } from 'next/navigation'

// Nhiệm vụ giờ là một tab trong màn Nhân Vật
export default function QuestsPage() {
  redirect('/?tab=quests')
}
