"""
Egregore Bot Evaluation Suite - LLM as Judge

Tests the bot end-to-end: asks questions, gets responses, 
then uses an LLM judge to evaluate response quality.

Run with: python test_bot.py
"""

import asyncio
import os
import json
import httpx
from dotenv import load_dotenv

load_dotenv()

# Import bot functions
from bot import agent_decide, run_query, QUERIES, format_response, generate_no_results_response, ANTHROPIC_API_KEY

# =============================================================================
# TEST QUESTIONS - Real organizational queries
# =============================================================================

TEST_CASES = [
    # Activity & Status
    {
        "question": "What's happening?",
        "intent": "Get recent team activity overview",
        "criteria": "Should mention recent work, people involved, or current focus areas"
    },
    {
        "question": "What's going on at Curve Labs?",
        "intent": "Understand current organizational activity",
        "criteria": "Should provide context about ongoing work or recent sessions"
    },
    
    # Person queries - should show ACTIVITY not just project assignments
    {
        "question": "What is Cem working on?",
        "intent": "Find out what Cem has been actively doing",
        "criteria": "Should show recent sessions/activity, NOT just list projects (everyone's on same projects)"
    },
    {
        "question": "Tell me about Oz",
        "intent": "Get Oz's recent activity",
        "criteria": "Should show what Oz has been doing recently - sessions, quests, or artifacts"
    },
    {
        "question": "What has Ali been doing?",
        "intent": "Find Ali's recent activity",
        "criteria": "Should show Ali's recent sessions or work logs"
    },
    
    # Quest queries  
    {
        "question": "What quests are active?",
        "intent": "List ongoing initiatives/explorations",
        "criteria": "Should list quest names/titles that are currently active"
    },
    {
        "question": "What quests did Cem start?",
        "intent": "Find quests initiated by Cem",
        "criteria": "Should list quests associated with Cem as starter/owner"
    },
    
    # Project queries
    {
        "question": "Tell me about lace",
        "intent": "Get details about the lace project",
        "criteria": "Should describe lace project, its domain (psyche), or related work"
    },
    {
        "question": "What projects do we have?",
        "intent": "List all projects",
        "criteria": "Should mention lace, tristero, infrastructure or similar"
    },
    
    # Search/artifact queries
    {
        "question": "What has Cem written?",
        "intent": "Find artifacts/content by Cem",
        "criteria": "Should list documents, articles, or artifacts by Cem"
    },
    {
        "question": "Find anything about grants",
        "intent": "Search for grant-related content",
        "criteria": "Should mention grant applications, NLNet, or funding-related items"
    },
    
    # Team queries
    {
        "question": "Who's on the team?",
        "intent": "List team members",
        "criteria": "Should mention oz, ali, cem or their full names"
    },
    
    # Follow-up style (harder - needs context inference)
    {
        "question": "Which ones did Cem start?",
        "context": "Previous question was about active quests",
        "intent": "Find quests Cem started (follow-up)",
        "criteria": "Should understand this refers to quests and list Cem's quests"
    },
    
    # Edge cases
    {
        "question": "Cem",
        "intent": "Single word - should show Cem's recent activity",
        "criteria": "Should show what Cem's been working on - sessions or quests, not just project list"
    },
    {
        "question": "lace",
        "intent": "Single word - should show info about lace project", 
        "criteria": "Should provide information about the lace project"
    },
    
    # General knowledge
    {
        "question": "How do I add something to the knowledge base?",
        "intent": "Learn how to contribute",
        "criteria": "Should explain the process or mention artifacts/commands"
    },
    {
        "question": "What is Egregore?",
        "intent": "Understand what Egregore is",
        "criteria": "Should explain Egregore as a knowledge system or collaborative org"
    },
]


async def get_bot_response(question: str, context: str = "") -> dict:
    """Get the full bot response for a question."""
    # Step 1: Agent decides what to do
    decision = await agent_decide(question, context)
    
    action = decision.get("action")
    
    if action == "respond":
        return {
            "response": decision.get("message", ""),
            "query_used": "direct_response",
            "data": None
        }
    
    if action == "query":
        query_name = decision.get("query")
        params = decision.get("params", {})
        
        if query_name not in QUERIES:
            return {
                "response": "Query not found",
                "query_used": query_name,
                "data": None
            }
        
        # Run the query
        cypher = QUERIES[query_name]["cypher"]
        results = run_query(cypher, params)
        
        if not results:
            # Use the new helpful no-results response
            response = await generate_no_results_response(question, query_name, params)
            return {
                "response": response,
                "query_used": query_name,
                "data": []
            }
        
        # Format response (with params for person context)
        response = await format_response(question, query_name, results, params)
        
        return {
            "response": response,
            "query_used": query_name,
            "data": results
        }
    
    return {
        "response": "Unknown action",
        "query_used": None,
        "data": None
    }


async def judge_response(question: str, intent: str, criteria: str, response: str) -> dict:
    """Use LLM to judge if the response is good."""
    
    system_prompt = """You are an evaluator judging if a chatbot response adequately answers a user's question.

Score from 1-5:
1 = Completely wrong or irrelevant
2 = Partially relevant but missing key information  
3 = Acceptable but could be better
4 = Good response that addresses the question
5 = Excellent, comprehensive response

Respond with JSON only: {"score": N, "reason": "brief explanation"}"""

    user_prompt = f"""Question: {question}
Intent: {intent}
Success criteria: {criteria}

Bot's response:
{response}

Evaluate this response."""

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "claude-haiku-4-5-20251001",
                    "max_tokens": 200,
                    "system": system_prompt,
                    "messages": [{"role": "user", "content": user_prompt}]
                },
                timeout=15
            )
            resp.raise_for_status()
            text = resp.json()["content"][0]["text"].strip()
            
            # Parse JSON
            if text.startswith("```"):
                text = text.split("```")[1]
                if text.startswith("json"):
                    text = text[4:]
                text = text.strip()
            
            return json.loads(text)
            
        except Exception as e:
            return {"score": 0, "reason": f"Judge error: {e}"}


async def run_evaluation():
    """Run full evaluation suite."""
    print("=" * 70)
    print("EGREGORE BOT EVALUATION - LLM AS JUDGE")
    print("=" * 70)
    print()
    
    results = []
    total_score = 0
    
    for i, test in enumerate(TEST_CASES, 1):
        question = test["question"]
        intent = test["intent"]
        criteria = test["criteria"]
        context = test.get("context", "")
        
        print(f"[{i:02d}] {question}")
        print(f"     Intent: {intent}")
        
        # Get bot response
        bot_result = await get_bot_response(question, context)
        response = bot_result["response"]
        query_used = bot_result["query_used"]
        
        # Truncate for display
        response_preview = response[:150] + "..." if len(response) > 150 else response
        print(f"     Query: {query_used}")
        print(f"     Response: {response_preview}")
        
        # Judge the response
        judgment = await judge_response(question, intent, criteria, response)
        score = judgment.get("score", 0)
        reason = judgment.get("reason", "No reason")
        
        total_score += score
        
        # Display result
        if score >= 4:
            status = "✓ GOOD"
        elif score >= 3:
            status = "○ OK"
        else:
            status = "✗ POOR"
        
        print(f"     {status} (Score: {score}/5) - {reason}")
        print()
        
        results.append({
            "question": question,
            "query_used": query_used,
            "score": score,
            "reason": reason
        })
    
    # Summary
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)
    
    avg_score = total_score / len(TEST_CASES)
    print(f"Average Score: {avg_score:.1f}/5")
    print(f"Total Tests: {len(TEST_CASES)}")
    
    good = sum(1 for r in results if r["score"] >= 4)
    ok = sum(1 for r in results if r["score"] == 3)
    poor = sum(1 for r in results if r["score"] < 3)
    
    print(f"Good (4-5): {good}")
    print(f"OK (3): {ok}")
    print(f"Poor (1-2): {poor}")
    
    if poor > 0:
        print()
        print("NEEDS IMPROVEMENT:")
        for r in results:
            if r["score"] < 3:
                print(f"  - '{r['question']}' (Score: {r['score']})")
                print(f"    Reason: {r['reason']}")
    
    return results


async def quick_test(question: str):
    """Quick test a single question."""
    print(f"\nQuestion: {question}")
    print("-" * 50)
    
    result = await get_bot_response(question)
    print(f"Query: {result['query_used']}")
    print(f"Data items: {len(result['data']) if result['data'] else 0}")
    print(f"\nResponse:\n{result['response']}")


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        # Quick test mode: python test_bot.py "What is Cem working on?"
        question = " ".join(sys.argv[1:])
        asyncio.run(quick_test(question))
    else:
        # Full evaluation
        asyncio.run(run_evaluation())
