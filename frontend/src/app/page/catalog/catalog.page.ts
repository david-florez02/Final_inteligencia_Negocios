import { HttpClient } from '@angular/common/http';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatSnackBar } from '@angular/material/snack-bar';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { SupabaseService, Product } from '../../core/supabase.service';
import { CartService } from '../../core/cart.service';

@Component({
  selector: 'app-catalog-page',
  standalone: true,
  imports: [RouterLink, DecimalPipe, FormsModule, MatCardModule, MatButtonModule, MatIconModule, MatInputModule, MatSelectModule, MatFormFieldModule],
  template: `
    <div class="toolbar">
      <mat-form-field appearance="outline" class="search">
        <mat-label>Buscar producto</mat-label>
        <input matInput [(ngModel)]="search" (ngModelChange)="load()" placeholder="MacBook, RTX 4080...">
      </mat-form-field>
      <mat-form-field appearance="outline" class="cat">
        <mat-label>Categoría</mat-label>
        <mat-select [(ngModel)]="categoryId" (selectionChange)="load()">
          <mat-option [value]="null">Todas</mat-option>
          @for (c of categories(); track c.id) { <mat-option [value]="c.id">{{ c.name }}</mat-option> }
        </mat-select>
      </mat-form-field>
      @if (app.isAdmin()) {
        <button mat-flat-button color="accent" routerLink="/admin">Panel admin</button>
      }
    </div>

    <div class="grid">
      @for (p of products(); track p.id) {
        <mat-card class="card">
          <img mat-card-image [src]="p.image_url ?? placeholder" [alt]="p.name">
          <mat-card-content>
            <h3>{{ p.name }}</h3>
            <p class="desc">{{ p.description }}</p>
            <p class="price">` + '$' + `{{ p.price | number:'1.2-2' }}</p>
            <p class="stock" [class.low]="p.stock <= 5">Stock: {{ p.stock }}</p>
          </mat-card-content>
          <mat-card-actions>
            <button mat-flat-button color="primary" (click)="addToCart(p)" [disabled]="p.stock === 0">
              @if (p.stock === 0) { Agotado } @else { Añadir al carrito }
            </button>
          </mat-card-actions>
        </mat-card>
      } @empty {
        <p>No se encontraron productos.</p>
      }
    </div>
  `,
  styles: [`
    .toolbar { display: flex; gap: 16px; align-items: center; flex-wrap: wrap; margin-bottom: 24px; }
    .search { min-width: 260px; flex: 1; }
    .cat { min-width: 200px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px; }
    .card img { height: 180px; object-fit: cover; }
    .desc { color: #616161; font-size: 13px; min-height: 38px; }
    .price { font-size: 20px; font-weight: 700; color: #00695c; }
    .stock.low { color: #e65100; font-weight: 600; }
  `],
})
export class CatalogPage implements OnInit, OnDestroy {
  private http = inject(HttpClient);
  private router = inject(Router);
  private snackBar = inject(MatSnackBar);
  readonly app = inject(SupabaseService);
  readonly cart = inject(CartService);

  readonly placeholder = 'https://placehold.co/600x400?text=Producto';
  readonly products = signal<Product[]>([]);
  readonly categories = signal<{ id: number; name: string }[]>([]);
  search = '';
  categoryId: number | null = null;

  ngOnInit(): void {
    this.http.get<{ id: number; name: string }[]>('/api/products/categories').subscribe({ next: (c) => this.categories.set(c) });
    this.load();
    this.app.subscribeToStock((payload: { id: number; stock: number }) => {
      this.products.update((list) => list.map((p) => p.id === payload.id ? { ...p, stock: payload.stock } : p));
    });
  }

  load(): void {
    const params: Record<string, string> = {};
    if (this.search) params['search'] = this.search;
    if (this.categoryId !== null) params['category_id'] = String(this.categoryId);
    this.http.get<Product[]>('/api/products', { params }).subscribe({ next: (p) => this.products.set(p) });
  }

  addToCart(p: Product): void {
    this.cart.add({ id: p.id, name: p.name, price: p.price, image_url: p.image_url });
    const ref = this.snackBar.open(`${p.name} se añadió al carrito`, 'Ver carrito', { duration: 3500 });
    ref.onAction().subscribe(() => void this.router.navigate(['/cart']));
  }

  ngOnDestroy(): void {
    // Libera el canal Realtime para que no siga alimentando a esta pagina tras salir de ella.
    this.app.unsubscribeFromStock();
  }
}
