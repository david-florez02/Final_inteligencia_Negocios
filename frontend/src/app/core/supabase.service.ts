import { Injectable, signal } from '@angular/core';
import { RealtimeChannel, createClient, Session, SupabaseClient, User } from '@supabase/supabase-js';
import { environment } from '../../environments/environment';

export interface Profile {
  id: string;
  full_name: string | null;
  phone: string | null;
  address: string | null;
  role: string;
}

export interface Product { id: number; name: string; description: string | null; price: number; stock: number; category_id: number | null; image_url: string | null; }

@Injectable({ providedIn: 'root' })
export class SupabaseService {
  private client: SupabaseClient = createClient(environment.supabaseUrl, environment.supabaseKey);
  session = signal<Session | null>(null);
  profile = signal<Profile | null>(null);
  private stockChannel: RealtimeChannel | null = null;

  constructor() {
    this.client.auth.getSession().then(({ data }) => this.session.set(data.session));
    this.client.auth.onAuthStateChange((_event, session) => {
      this.session.set(session);
      if (session) void this.loadProfile(session.user.id);
      else this.profile.set(null);
    });
  }

  get user(): User | null { return this.session()?.user ?? null; }
  isAdmin(): boolean { return this.profile()?.role === 'admin'; }

  async signIn(email: string, password: string): Promise<{ error: string | null }> {
    const { data, error } = await this.client.auth.signInWithPassword({ email, password });
    if (!error && data.session) {
      this.session.set(data.session);
      await this.loadProfile(data.session.user.id);
    }
    return { error: error ? error.message : null };
  }

  async signUp(email: string, password: string): Promise<{ error: string | null }> {
    const { data, error } = await this.client.auth.signUp({ email, password });
    if (!error && data.session) {
      this.session.set(data.session);
      await this.loadProfile(data.session.user.id);
    }
    return { error: error ? error.message : null };
  }

  async signOut(): Promise<void> { await this.client.auth.signOut(); this.session.set(null); }

  async loadProfile(userId: string): Promise<void> {
    const { data } = await this.client.from('users_profile').select('*').eq('id', userId).maybeSingle();
    this.profile.set((data as Profile) ?? null);
  }

  private token(): Promise<string | null> { return this.client.auth.getSession().then(r => r.data.session?.access_token ?? null); }

  async authHeaders(): Promise<Record<string, string>> {
    const token = await this.token();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
  }

  subscribeToStock(onStockChange: (payload: { id: number; stock: number }) => void): void {
    if (this.stockChannel) return;
    this.stockChannel = this.client.channel('stock-updates');
    this.stockChannel.on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'products' },
      (payload) => onStockChange(payload.new as { id: number; stock: number }))
      .subscribe();
  }

  unsubscribeFromStock(): void {
    if (this.stockChannel) { void this.client.removeChannel(this.stockChannel); this.stockChannel = null; }
  }
}
