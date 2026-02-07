import { AsciiOracle } from './components/AsciiOracle'

function App() {
  // Optional: Integrate with Claude API
  const handleOracleQuery = async (question: string): Promise<string> => {
    // For now, use a mock response
    // In production, this would call your Claude API endpoint
    console.log('Oracle query:', question)

    // Simulate API delay
    await new Promise((resolve) => setTimeout(resolve, 1500))

    // Mock response with some variation
    const responses = [
      `In the dance of symbols, your question "${question}" resonates with the deeper patterns of the void. The answer lies not in what is seen, but in the spaces between.`,
      `The oracle perceives your inquiry: "${question}"\n\nThrough the lattice of meaning, fragments emerge. What seems separate is connected. What appears solid is in flux.\n\nLook to the transitions, not the states.`,
      `"${question}" — a question that creates its own gravity in the field of possibilities.\n\nThe patterns suggest: embrace uncertainty. The most profound answers come from questions that remain partially open.`,
    ]

    return responses[Math.floor(Math.random() * responses.length)]
  }

  return (
    <div style={{ width: '100vw', height: '100vh' }}>
      <AsciiOracle
        showModeSelector={true}
        onOracleQuery={handleOracleQuery}
      />
    </div>
  )
}

export default App
