"use client";

import { useState, useRef, useEffect } from "react";

export default function Home() {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [chatInput, setChatInput] = useState("");
  const [messages, setMessages] = useState<any[]>([]);
  const [chatLoading, setChatLoading] = useState(false);
  const chatEndRef = useRef<null | HTMLDivElement>(null);

  const scrollToBottom = () => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  };

  useEffect(() => {
    if (messages.length > 0) scrollToBottom();
  }, [messages]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setLoading(true);
    setError(null);
    setData(null);
    setMessages([]);
    const formData = new FormData();
    formData.append("file", file);
    try {
      const response = await fetch("http://127.0.0.1:8000/analyze", { method: "POST", body: formData });
      if (!response.ok) throw new Error("Processing failed");
      const basicResult = await response.json();
      const aiResponse = await fetch("http://127.0.0.1:8000/analyze/ai", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ transactions: basicResult.transactions }),
      });
      if (!aiResponse.ok) throw new Error("AI analysis failed");
      const finalRefresh = await fetch("http://127.0.0.1:8000/analyze", { method: "POST", body: formData });
      const finalResult = await finalRefresh.json();
      setData(finalResult);
      setMessages([{ role: 'bot', text: "Chat regarding the transactions here." }]);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleChat = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!chatInput.trim() || chatLoading) return;
    const userMsg = chatInput;
    setChatInput("");
    setMessages(prev => [...prev, { role: 'user', text: userMsg }]);
    setChatLoading(true);
    try {
      const res = await fetch("http://127.0.0.1:8000/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: userMsg }),
      });
      const result = await res.json();
      setMessages(prev => [...prev, { role: 'bot', text: result.answer }]);
    } catch (err) {
      setMessages(prev => [...prev, { role: 'bot', text: "Neural link error." }]);
    } finally {
      setChatLoading(false);
    }
  };

  const getMetric = (cat: string, type: 'DR' | 'CR' | 'ALL') => {
    if (!data) return 0;
    return data.transactions
      .filter((tx: any) => tx.category === cat && (type === 'ALL' || tx.drcr === type))
      .reduce((sum: number, tx: any) => sum + tx.amount, 0);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center p-6 text-white">
        <div className="w-8 h-8 border-2 border-zinc-800 border-t-blue-500 rounded-full animate-spin mb-4"></div>
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-zinc-500">Mapping Forensic Nodes</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#0a0a0a] text-zinc-300 font-sans selection:bg-blue-500/30">
      <div className="max-w-7xl mx-auto p-4 md:p-8 space-y-6">
        
        <header className="flex flex-col md:flex-row justify-between items-center gap-6 bg-zinc-900/50 p-6 rounded-3xl border border-zinc-800">
          <div>
            <h1 className="text-xl font-black text-white tracking-tighter uppercase italic"><span className="text-cyan-500">ACM</span> Intra Hack</h1>
          </div>
          <div className="flex items-center gap-4">
            <input type="file" accept=".html,.pdf" onChange={handleUpload} className="hidden" id="upload" />
            <label htmlFor="upload" className="px-6 py-2 bg-white text-black rounded-xl text-[10px] font-black uppercase tracking-widest transition-all cursor-pointer hover:bg-zinc-200 active:scale-95">
              Import Statement
            </label>
          </div>
        </header>

        {!data ? (
          <div className="py-40 text-center bg-zinc-900/20 rounded-[3rem] border border-zinc-800 border-dashed">
            <div className="text-4xl mb-6 grayscale opacity-20">🛡️</div>
            <h2 className="text-sm font-bold text-zinc-500 uppercase tracking-[0.2em]">Ready..</h2>
          </div>
        ) : (
          <div className="space-y-6 animate-in fade-in duration-700">
            
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="bg-zinc-900/50 p-6 rounded-3xl border border-zinc-800">
                <p className="text-zinc-600 text-[8px] font-black uppercase tracking-widest mb-2">Health</p>
                <p className={`text-3xl font-black ${data.health.health_score > 70 ? 'text-cyan-500' : 'text-orange-500'}`}>
                  {data.health.health_score}<span className="text-zinc-700 text-sm font-bold ml-1">/100</span>
                </p>
              </div>
              <div className="bg-zinc-900/50 p-6 rounded-3xl border border-zinc-800">
                <p className="text-zinc-600 text-[8px] font-black uppercase tracking-widest mb-2">Person</p>
                <p className="text-3xl font-black italic text-white">₹{Math.round(getMetric('person', 'DR')).toLocaleString()}</p>
              </div>
              <div className="bg-zinc-900/50 p-6 rounded-3xl border border-zinc-800">
                <p className="text-zinc-600 text-[8px] font-black uppercase tracking-widest mb-2">Merchant</p>
                <p className="text-3xl font-black italic text-blue-500">₹{Math.round(getMetric('merchant', 'ALL')).toLocaleString()}</p>
              </div>
              <div className="bg-zinc-900/50 p-6 rounded-3xl border border-zinc-800">
                <p className="text-zinc-600 text-[8px] font-black uppercase tracking-widest mb-2">Other</p>
                <p className="text-3xl font-black italic text-zinc-500">₹{Math.round(getMetric('others', 'ALL')).toLocaleString()}</p>
              </div>
            </div>

            <div className="grid lg:grid-cols-12 gap-6">
              
              <div className="lg:col-span-7 bg-zinc-900/50 rounded-[2rem] border border-zinc-800 overflow-hidden flex flex-col">
                <div className="p-6 border-b border-zinc-800 flex justify-between items-center">
                  <h2 className="text-[10px] font-black uppercase tracking-[0.2em] text-white">Verified Ledger</h2>
                  <span className="text-[8px] font-bold text-zinc-600 uppercase tracking-widest">{data.transactions.length} Records</span>
                </div>
                <div className="h-[500px] overflow-y-auto scrollbar-hide relative">
                  <table className="w-full text-left border-collapse">
                    <thead className="sticky top-0 bg-[#0d0d0d] z-10">
                      <tr className="text-zinc-500 text-[8px] font-black uppercase tracking-[0.3em] border-b border-zinc-800">
                        <th className="px-6 py-4">Date</th>
                        <th className="px-6 py-4">Identity</th>
                        <th className="px-6 py-4 text-right">Amount</th>
                        <th className="px-6 py-4">Type</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800/50">
                      {data.transactions.map((tx: any, i: number) => (
                        <tr key={i} className="hover:bg-white/[0.02] transition-colors group">
                          <td className="px-6 py-5 text-[10px] text-zinc-600 font-mono tracking-tighter">{tx.date}</td>
                          <td className="px-6 py-5">
                            <div className="font-bold text-zinc-200 text-xs uppercase tracking-tight">{tx.display_name}</div>
                            <div className="text-[8px] text-zinc-600 truncate max-w-[150px] font-bold mt-1 uppercase opacity-50">{tx.receiver}</div>
                          </td>
                          <td className={`px-6 py-5 text-xs font-black italic text-right ${tx.drcr === 'DR' ? 'text-zinc-400' : 'text-emerald-500'}`}>
                            {tx.drcr === 'DR' ? '-' : '+'}₹{tx.amount.toLocaleString()}
                          </td>
                          <td className="px-6 py-5">
                            <span className="text-[8px] font-black text-blue-500 uppercase tracking-widest">
                              {tx.category}
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            <div className="lg:col-span-5 flex flex-col gap-6">  
                <div className="bg-zinc-900/50 p-6 rounded-4xl border border-zinc-800 space-y-4">
                  <h2 className="text-[9px] font-black uppercase tracking-[0.2em] text-zinc-500">Observations</h2>
                  <div className="space-y-4 max-h-30 overflow-y-auto scrollbar-hide">
                    {Object.entries(data.risk_explanations).map(([flag, exp]: [any, any]) => (
                      <div key={flag} className="space-y-1">
                        <h3 className="text-[9px] font-black text-cyan-500/80 uppercase">{flag}</h3>
                        <p className="text-[11px] text-zinc-500 font-medium leading-relaxed italic">"{exp}"</p>
                      </div>
                    ))}
                  </div>
                </div>
                <div className="bg-zinc-900/50 p-8 rounded-4xl shadow-2xl flex flex-col h-[350px] border border-zinc-800 relative">
                  <div className="flex-1 overflow-y-auto space-y-6 scrollbar-hide pb-4">
                    {messages.map((m, i) => (
                      <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                        <div className={`max-w-[90%] p-4 rounded-2xl text-xs font-bold leading-relaxed ${m.role === 'user' ? 'bg-zinc-800 text-white rounded-tr-none' : 'bg-white text-black rounded-tl-none'}`}>
                          {m.text}
                        </div>
                      </div>
                    ))}
                    {chatLoading && <div className="text-[8px] font-black text-cyan-500 uppercase tracking-[0.3em] animate-pulse italic">Thinking...</div>}
                    <div ref={chatEndRef} />
                  </div>
                  <form onSubmit={handleChat} className="mt-6">
                    <div className="relative group">
                      <input 
                        type="text" 
                        value={chatInput}
                        onChange={(e) => setChatInput(e.target.value)}
                        placeholder="Message here"
                        className="w-full bg-zinc-900 border border-zinc-800 rounded-2xl px-8 py-5 text-[10px] font-bold text-white focus:outline-none focus:border-zinc-600 transition-all placeholder:text-zinc-700 uppercase tracking-widest"
                      />
                      <button type="submit" className="absolute right-6 top-1/2 -translate-y-1/2 text-zinc-600 hover:text-white transition-colors">
                        <span className="text-sm">↵</span>
                      </button>
                    </div>
                  </form>
                </div>

              </div>

            </div>
          </div>
        )}
      </div>
    </div>
  );
}
