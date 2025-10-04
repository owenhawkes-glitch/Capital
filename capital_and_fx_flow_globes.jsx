/*
Capital-and-FX-Flow-Globes.jsx

Prototype React single-file app that:
 - Fetches external datasets (configurable URLs) for capital flows (CSV) and FX flows (JSON)
 - Parses them into origin-destination arrays
 - Falls back to embedded demo data when fetch fails
 - Renders two interactive globes (capital & FX) using react-globe.gl

Notes:
 - To run in CodeSandbox / locally install: react, react-dom, three, react-globe.gl
 - The component tries to fetch two sample URLs (editable):
     CAPITAL_URL (CSV) expected columns: origin_country,origin_lat,origin_lng,dest_country,dest_lat,dest_lng,value
     FX_URL (JSON) expected format: [{"origin":"USD","dest":"EUR","value":...}, ...]
 - If remote fetch fails, embedded sample data used.

*/

import React, { useEffect, useRef, useState } from 'react'
import Globe from 'react-globe.gl'

// --- Config: replace these with direct links to CSV/JSON endpoints if available ---
const CAPITAL_URL = 'https://example.com/capital-flows-sample.csv' // CSV
const FX_URL = 'https://example.com/fx-flows-sample.json' // JSON

// --- Utility CSV parser (very small, tolerant) ---
function parseCSV(text){
  const lines = text.trim().split(/?
/)
  const headers = lines.shift().split(',').map(h=>h.trim())
  return lines.map(l=>{
    const cols = l.split(',')
    const obj = {}
    headers.forEach((h,i)=> obj[h]=cols[i]===undefined? '': cols[i].trim())
    return obj
  })
}

export default function CapitalAndFxGlobes(){
  const globeEl1 = useRef()
  const globeEl2 = useRef()
  const [mode, setMode] = useState('both')
  const [capitalFlows, setCapitalFlows] = useState(null)
  const [fxFlows, setFxFlows] = useState(null)
  const [loading, setLoading] = useState(true)
  const [errors, setErrors] = useState([])

  // --- Embedded fallback sample data ---
  const fallbackCapital = [
    { origin: { lat: 40.7128, lng: -74.0060, country: 'United States' }, dest: { lat: 51.5074, lng: -0.1278, country: 'United Kingdom' }, value: 1200 },
    { origin: { lat: 48.8566, lng: 2.3522, country: 'France' }, dest: { lat: 35.6895, lng: 139.6917, country: 'Japan' }, value: 700 },
    { origin: { lat: 1.3521, lng: 103.8198, country: 'Singapore' }, dest: { lat: 37.7749, lng: -122.4194, country: 'United States (SF)' }, value: 400 }
  ]

  const fallbackFx = [
    { origin: 'USD', dest: 'EUR', value: 2500 },
    { origin: 'USD', dest: 'JPY', value: 1800 },
    { origin: 'GBP', dest: 'USD', value: 900 },
    { origin: 'EUR', dest: 'JPY', value: 600 }
  ]

  const currencyHubs = {
    USD: { lat: 38.9072, lng: -77.0369, label: 'USD (Washington)' },
    EUR: { lat: 50.1109, lng: 8.6821, label: 'EUR (Frankfurt)' },
    JPY: { lat: 35.6762, lng: 139.6503, label: 'JPY (Tokyo)' },
    GBP: { lat: 51.5074, lng: -0.1278, label: 'GBP (London)' }
  }

  // --- Convert flows to react-globe arc objects ---
  const makeArcsFromCapital = (flows) => flows.map(f => ({
    startLat: f.origin.lat, startLng: f.origin.lng,
    endLat: f.dest.lat, endLng: f.dest.lng,
    color: ['rgba(0,150,255,0.9)', 'rgba(0,255,150,0.6)'],
    dashLength: 0.4,
    stroke: Math.min(10, Math.log10(f.value + 1) * 2 + 0.5),
    value: f.value,
    label: `${f.origin.country} → ${f.dest.country}: ${f.value}`
  }))

  const makeArcsFromFx = (flows) => flows.map(f => ({
    startLat: (currencyHubs[f.origin]||{lat:0}).lat, startLng: (currencyHubs[f.origin]||{lng:0}).lng,
    endLat: (currencyHubs[f.dest]||{lat:0}).lat, endLng: (currencyHubs[f.dest]||{lng:0}).lng,
    color: ['rgba(255,120,0,0.9)', 'rgba(255,220,0,0.6)'],
    dashLength: 0.25,
    stroke: Math.min(12, Math.sqrt(f.value) / 5),
    value: f.value,
    label: `${f.origin} → ${f.dest}: ${f.value} (notional)`
  }))

  // --- Fetching logic: try remote then fallback ---
  useEffect(()=>{
    let cancelled = false
    async function load(){
      setLoading(true)
      const errs = []

      // Try capital CSV
      try{
        const r = await fetch(CAPITAL_URL)
        if(!r.ok) throw new Error('Capital fetch failed: ' + r.status)
        const txt = await r.text()
        const rows = parseCSV(txt)
        const flows = rows.map(rw=>({
          origin: { lat: parseFloat(rw.origin_lat), lng: parseFloat(rw.origin_lng), country: rw.origin_country },
          dest: { lat: parseFloat(rw.dest_lat), lng: parseFloat(rw.dest_lng), country: rw.dest_country },
          value: Number(rw.value || rw.amount || 0)
        })).filter(x=>!isNaN(x.origin.lat) && !isNaN(x.dest.lat))
        if(!cancelled && flows.length) setCapitalFlows(flows)
      }catch(e){
        errs.push('Capital data load failed — using fallback')
        if(!cancelled) setCapitalFlows(fallbackCapital)
      }

      // Try FX JSON
      try{
        const r2 = await fetch(FX_URL)
        if(!r2.ok) throw new Error('FX fetch failed: ' + r2.status)
        const j = await r2.json()
        // Expect array of {origin, dest, value}
        if(Array.isArray(j) && j.length>0) setFxFlows(j)
        else throw new Error('FX JSON not array')
      }catch(e){
        errs.push('FX data load failed — using fallback')
        if(!cancelled) setFxFlows(fallbackFx)
      }

      if(!cancelled){ setErrors(errs); setLoading(false) }
    }
    load()
    return ()=>{ cancelled = true }
  }, [])

  useEffect(() =>{
    globeEl1.current && (globeEl1.current.controls().autoRotate = true)
    globeEl2.current && (globeEl2.current.controls().autoRotate = true)
  }, [])

  // Prepare arcs for rendering
  const capitalArcs = capitalFlows ? makeArcsFromCapital(capitalFlows) : []
  const fxArcs = fxFlows ? makeArcsFromFx(fxFlows) : []

  const Hud = ({ title }) => (
    <div style={{ position: 'absolute', left: 12, top: 12, background: 'rgba(0,0,0,0.6)', color: 'white', padding: 8, borderRadius:8, maxWidth: 320 }}>
      <div style={{ fontWeight: 600 }}>{title}</div>
      <div style={{ fontSize: 12, opacity: 0.85 }}>Drag to rotate · Scroll to zoom · Hover arcs for info</div>
    </div>
  )

  return (
    <div style={{ minHeight: '100vh', background: '#0b1220', color: 'white', padding: 20, boxSizing: 'border-box' }}>
      <div style={{ maxWidth: 1100, margin: '0 auto' }}>
        <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
          <h1 style={{ margin:0, fontSize: 20 }}>Capital & FX Flow Globes — Prototype</h1>
          <div style={{ display: 'flex', gap:8 }}>
            <button onClick={()=>setMode('both')} style={{ padding: '6px 10px' , background: mode==='both'? '#0b6cff' : '#162233', color: 'white', border:0, borderRadius:6 }}>Both</button>
            <button onClick={()=>setMode('capital')} style={{ padding: '6px 10px' , background: mode==='capital'? '#0b6cff' : '#162233', color: 'white', border:0, borderRadius:6 }}>Capital</button>
            <button onClick={()=>setMode('fx')} style={{ padding: '6px 10px' , background: mode==='fx'? '#0b6cff' : '#162233', color: 'white', border:0, borderRadius:6 }}>FX</button>
          </div>
        </header>

        <div style={{ display: 'grid', gridTemplateColumns: mode==='both' ? '1fr 1fr' : '1fr', gap: 12 }}>
          {(mode==='both' || mode==='capital') && (
            <div style={{ position:'relative', borderRadius:12, overflow:'hidden', border: '1px solid rgba(255,255,255,0.06)' }}>
              <Hud title={loading ? 'Loading data...' : 'Capital / Equity Flows'} />
              <Globe
                ref={globeEl1}
                globeImageUrl="https://unpkg.com/three-globe/example/img/earth-night.jpg"
                backgroundColor="rgba(0,0,0,0)"
                arcsData={capitalArcs}
                arcStartLat={d => d.startLat}
                arcStartLng={d => d.startLng}
                arcEndLat={d => d.endLat}
                arcEndLng={d => d.endLng}
                arcColor={d => d.color}
                arcDashLength={d => d.dashLength}
                arcDashGap={0.4}
                arcDashAnimateTime={() => 4000}
                arcAltitude={d => 0.08 + Math.log10(d.value+1) / 10}
                arcStroke={d => d.stroke}
                onArcHover={(d) => { if(d) globeEl1.current && (globeEl1.current.controls().autoRotate = false) }}
                onArcOut={() => globeEl1.current && (globeEl1.current.controls().autoRotate = true)}
                width={600}
                height={600}
              />
            </div>
          )}

          {(mode==='both' || mode==='fx') && (
            <div style={{ position:'relative', borderRadius:12, overflow:'hidden', border: '1px solid rgba(255,255,255,0.06)' }}>
              <Hud title={loading ? 'Loading data...' : 'Forex / Currency Flows (notional)'} />
              <Globe
                ref={globeEl2}
                globeImageUrl="https://unpkg.com/three-globe/example/img/earth-night.jpg"
                backgroundColor="rgba(0,0,0,0)"
                arcsData={fxArcs}
                arcStartLat={d => d.startLat}
                arcStartLng={d => d.startLng}
                arcEndLat={d => d.endLat}
                arcEndLng={d => d.endLng}
                arcColor={d => d.color}
                arcDashLength={d => d.dashLength}
                arcDashGap={0.25}
                arcDashAnimateTime={() => 2500}
                arcAltitude={d => 0.04 + Math.log10(d.value+1) / 8}
                arcStroke={d => d.stroke}
                arcsTransitionDuration={300}
                labelsData={Object.keys(currencyHubs).map(k => ({ ...currencyHubs[k], id: k }))}
                labelLat={d => d.lat}
                labelLng={d => d.lng}
                labelText={d => d.label}
                labelSize={d => 1.2}
                labelResolution={2}
                width={600}
                height={600}
              />
            </div>
          )}
        </div>

        <footer style={{ marginTop:12, fontSize: 13, color: '#c9d2df' }}>
          <div style={{ marginBottom:6 }}><strong>Data sources:</strong> Replace the CAPITAL_URL and FX_URL constants with direct links to IMF / BIS / World Bank CSV or JSON exports. The component will try to fetch and parse them automatically. If fetch fails the embedded demo dataset is used.</div>
          <div style={{ color: '#9aa6b2' }}>{errors.join(' · ')}</div>
        </footer>
      </div>
    </div>
  )
}
