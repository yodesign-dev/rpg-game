import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import DummyTester from './DummyTester'

export default async function TrainingPage() {
  const { character } = await getCurrentCharacter()
  return (
    <GlassPage back title="Nộm Tập" subtitle="Đánh 30 lượt vào nộm để đo sát thương. Không tốn AP, không mất HP — thử build thoải mái.">
      <DummyTester characterId={character.id} />
    </GlassPage>
  )
}
