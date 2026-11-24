import { createContext,useContext,useEffect,useState } from 'react';import type{ReactNode}from'react';import type{User}from '@supabase/supabase-js';import{supabase}from '../../lib/supabase';import type{Role}from '../../lib/types';
type Auth={user:User|null;role:Role|null;loading:boolean;refresh:()=>Promise<void>};const Context=createContext<Auth|null>(null);
export function AuthProvider({children}:{children:ReactNode}){const[user,setUser]=useState<User|null>(null);const[role,setRole]=useState<Role|null>(null);const[loading,setLoading]=useState(true);
async function refresh(){const {data}=await supabase.auth.getUser();setUser(data.user);if(data.user){const p=await supabase.from('profiles').select('role').eq('id',data.user.id).maybeSingle();setRole((p.data?.role as Role)||null)}else setRole(null);setLoading(false)}
useEffect(()=>{void refresh();const{data}=supabase.auth.onAuthStateChange(()=>{setTimeout(()=>void refresh(),0)});return()=>data.subscription.unsubscribe()},[]);return <Context.Provider value={{user,role,loading,refresh}}>{children}</Context.Provider>}
export function useAuth(){const v=useContext(Context);if(!v)throw Error('AuthProvider missing');return v}
