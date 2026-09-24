import { redirect } from 'next/navigation'

// Thiên phú giờ là một tab trong màn Nhân Vật
export default function TalentsPage() {
  redirect('/?tab=talents')
}
